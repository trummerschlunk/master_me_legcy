/* automatic mastering chain for the ccrma 'Quarantine Sessions'*/
/*
 *  Copyright (C) 2020 Klaus Scheuermann, klaus@4ohm.de
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; version 2 of the License.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 */

/* some building blocks where taken from or inspired by Dario Sanfilippo <sanfilippo.dario at gmail dot com
 * some building blocks by Stéphane Letz
 * a lot of help came from the faust community, especially sletz, magnetophone and dario sanphilippo
*/

declare name      "masterme_gui";
declare author    "Klaus Scheuermann";
declare version   "0.09.13";
declare copyright "(C) 2020 Klaus Scheuermann";

import("stdfaust.lib");

// main
process = _,_ : 
        input_meter : 
        ba.bypass2(checkbox("bypass all"), 
        gain : dc : leveler_stereo : multi_ms_comp : limiter_dario : diffN_cubic(cubic_st(4))) : 
        output_meter;

// functions

// input and out metering (stereo)
input_meter = hgroup("tabA", hgroup("[0]Input",vmeter)), hgroup("tabA", hgroup("[0]Input",vmeter));
output_meter = hgroup("tabA", hgroup("[9]Output",vmeter)), hgroup("tabA", hgroup("[9]Output",vmeter));

// gain (stereo)
g = hgroup("tabA", vgroup("[1]Input Gain",vslider("gain",16,1,50,0.01)));
gain = _ * g, _ * g;

// dc filter (stereo)
dc = fi.dcblocker,fi.dcblocker;

// UNUSED: Dario Sanfilippo Leveler Original (mono)
leveler_orig = _ *16 <: ((ma.tanh <: * : fi.lowpass(1, .1) : sqrt) - 1 : abs), _ : *;

// leveler with high-pass filer on the regulating path (mono)
leveler = _ *16 <:  (fi.highpass(2,60):(ma.tanh <: * : fi.lowpass(1, t) : sqrt) - 1 : abs), _ : *
    with {
        t = 0.1;//hslider("leveler time", 0.1,0.01,1,0.01);
    };

// leveler with high-pass filer on the regulating path (dual-mono)
leveler_dualmono = leveler*0.3,leveler*0.3;

// leveler with high-pass filer on the regulating path (stereo linked)
leveler_stereo = _,_ <: (_,calcAB : *), (_,calcAB : *) : _,_;

calcAux = (fi.highpass(2,60):(ma.tanh <: * : fi.lowpass(1, t) : sqrt) - 1 : abs)
	with {
        t = hgroup("tabA", vgroup("[2]GR Leveler",hslider("leveler time", 0.05,0.01,1,0.01)));
    };

calcA = calcAux;
calcB = calcAux;

calcAB = max(calcA,calcB) : hgroup("tabA", vgroup("[2]GR Leveler",neg_vmeter));

// stereo to m/s encoder
ms_enc = _*0.5,_*0.5 <: +, -;

// m/s to stereo decoder
ms_dec = _,_ <: +, -;

// 3-band splitter stereo
split3 = _,_ : fi.filterbank(3, (250,2500)), fi.filterbank(3, (250,2500)) : _,_,_,_,_,_;

// 3-band joiner stereo
join3 = (si.bus(3) :> _) , (si.bus(3) :> _);

// drywet mono
drywet(w,fx) = _ <: _, fx : *(1-w) , *(w) :> _;
  
// n channel (parallel) compressor
comp(n,ratio,thresh,att,rel,w) = par(i,n, drywet(w,co.compressor_mono(ratio,thresh, att, rel)));

// multiband m/s compressor (no channel linking)
multi_ms_comp =  ms_enc : split3 : diffN_mb(comp(6,2,-16,0.02,0.05,0.6)) : join3 : ms_dec;

// config of Dario's Lookahead Limiter
limiter_dario = limiter_lookaheadN(2,.01, 0.8 , .001, .005, 0.1);

// multichannel lookahead Limiter by Dario Snafilippo
limiter_lookaheadN(N, lag, threshold, attack, hold, release) = 
si.bus(N) <: par(i, N, @ (lag * ma.SR)) , (scaling <: si.bus(N)) : ro.interleave(N, 2) : par(i, N, *)
    with {
        scaling = threshold , amp_profile : / : min(1) : hgroup("tabA", vgroup("[4]GR Lookahead_Limiter",neg_vmeter));
        amp_profile = par(i, N, abs) : maxN(N) : ba.peakholder(hold * ma.SR) :
        att_smooth(attack) : rel_smooth(release);
        att_smooth(time, in) = si.smooth(ba.tau2pole(time), in);
        rel_smooth(time, in) = peak_env(time, in);
        peak_env(release, in) = abs(in) : max ~ *(ba.tau2pole(release));
        maxN(1) = _;
        maxN(2) = max(_ , _);
        maxN(N) = max(maxN(N - 1));
    };

// cubic nonlinear distortion by Dario Sanfilippo
cubic(x) = select3(cond, -2/3, x-(x*x*x/3), 2/3)
    with {
        cond = ((x : >(-1)),
                (x : <(1)) : &),
            	(x : >=(1))*2 :> _;
    };
cubic_st(d) = _/d,_/d : cubic, cubic : _*d,_*d;

// metering
vmeter(x)       = attach(x, envelop(x) : vbargraph("[unit:dB]", -70, 0));
hmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:dB]", -70, 0));
dmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:db]", -12, 12));
gmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:db]", 0, 12));
fmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:db]", 0, 12));
gvmeter(x)      = attach(x, envelop(x) : vbargraph("[unit:db]", 0, 12));
neg_vmeter(x)   = attach(x, envelop(x) : abs : hbargraph("[unit:db]", 0, 12));
envelop         = abs : max(ba.db2linear(-70)) : ba.linear2db : min(10)  : max ~ -(10.0/ma.SR);
envelop_neg     = abs : max(ba.db2linear(-70)) : ba.linear2db : min(10)  : max ~ -(10.0/ma.SR);

// functions for gain-reduction metering

diffn(n,fx) = par(i,n, _ <: attach(fx,(_ <: fx,_ : - : dmeter)));
diff1(fx) = _ <: attach(fx,(_ <: fx,_ : - : gmeter));

//  diffN_meter by Stéphane Letz
diffN_meter(meter, fx) = m_in <: fx,(m_in <: (fx,m_in) 
            : ro.interleave(ins,2) : m_sub : m_dmeter) 
            : ro.interleave(ins,2) : m_attach
with {
    ins = inputs(fx);
    m_in = par(i,ins,_);
    m_sub = par(i,ins,m_gr);
    m_dmeter = par(i,ins,meter);
    m_attach = par(i,ins,attach);
    m_gr(fx) = _ <: (1 -(fx,_ : -));
};

// Use of previous generic function with partial application (giving the first 'meter' parameter)
diffN_mb = diffN_meter(hgroup("tabA",vgroup("[3]GR mb_ms_comp", gmeter)));

diffN_cubic = diffN_meter(hgroup("tabA", vgroup("[5]GR cubic_clipper", gmeter)));
