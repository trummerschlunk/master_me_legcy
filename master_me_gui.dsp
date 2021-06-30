/* automatic mastering chain for the ccrma 'Quarantine Sessions'*/
/*
 *  Copyright (C) 2021 Klaus Scheuermann, klaus@4ohm.de
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
declare version   "2.0";
declare copyright "(C) 2021 Klaus Scheuermann";
import("stdfaust.lib");



// main
process(x1, x2) = x1,x2 : 
    input_meter : 
    dc : 
    ba.bypass2(checkbox("bypass all"), 
    leveler_stereo( max( abs(x1),abs(x2) ) ) : 
    gain(-2) : 
    multi_ms_comp6 : 
    gain(0) : 
    diffN_limiter(limiter) :
    gain(8)  : 
    (co.limiter_lad_bw, co.limiter_lad_bw) ) : 
    output_meter;



// simple gain function (stereo)
gain(x) = _ * (x :ba.db2linear) , _ * (x :ba.db2linear);

// dc filter (stereo)
dc = fi.dcblocker,fi.dcblocker;

// leveler
leveler_stereo(sc, x1, x2) = x1 * g * calc(sc), x2 * g * calc(sc);

// leveler headroom gain
g = hgroup("tabA", vgroup("[1]Headroom",vslider("gain[unit:dB]",20,0,30,1))) : si.smoo :ba.db2linear;

// leveler calculation
calc(sc) = sc * 6 * g : fi.highpass(2,50) : (ma.tanh <: * : lp1p(tg) : sqrt) - 1 : abs : ba.linear2db *1.5 : hgroup("tabA", vgroup("[2]Leveler", hbargraph("[1]gain reduction[unit:dB]",-36,0))) : ba.db2linear 
with {
    t= hgroup("tabA", vgroup("[2]Leveler",hslider("[3]leveler speed", 0.02,0.01,0.1,0.01))) ;
    tg = gate(sc) * t : hgroup("tabA", vgroup("[2]Leveler", hbargraph("[2]leveler speed with gate",0,0.1))) ; 
};

lp1p(cf, x) = +(x * (1 - b)) ~ (*(b) + init)
    with {
        //init = .5 - .5';
        init = 0.65 - 0.65';
        b = exp(-2 * ma.PI * cf / ma.SR);
    };

gate(sc) = gate_gain_mono(g_thr, 0.01, 0.2, 0.1, abs(sc) ) with {
    g_thr = hgroup("tabA", vgroup("[2]Leveler",hslider("gate threshold[unit:dB]", -60,-90,0,1)));
    };

// from library
gate_gain_mono(thresh,att,hold,rel,x) = x : extendedrawgate : an.amp_follower_ar(att,rel) with {
  extendedrawgate(x) = max(float(rawgatesig(x)),holdsig(x));
  rawgatesig(x) = inlevel(x) > ba.db2linear(thresh);
  minrate = min(att,rel);
  inlevel = an.amp_follower_ar(minrate,minrate);
  holdcounter(x) = (max(holdreset(x) * holdsamps,_) ~-(1));
  holdsig(x) = holdcounter(x) > 0;
  holdreset(x) = rawgatesig(x) < rawgatesig(x)'; // reset hold when raw gate falls
  holdsamps = int(hold*ma.SR);
};





//variable t fpr  future use
//brake(sc) = sc : an.abs_envelope_rect(1) ^(0.1)  : hgroup("tabA", vgroup("[2]GR Leveler", hbargraph("brake",0,1)));

// stereo to m/s encoder
ms_enc = _*0.5,_*0.5 <: +, -;
// m/s to stereo decoder
ms_dec = _,_ <: +, -;
// 3-band splitter stereo
split3 = _,_ : fi.filterbank(3, (250,2500)), fi.filterbank(3, (250,2500)) : _,_,_,_,_,_;
// 3-band joiner stereo
join3 = (si.bus(3) :> _) , (si.bus(3) :> _);

// 6ch FB compressor + mb_ms version
comp6 = co.FBcompressor_N_chan(0.6,-15,0.02,0.5,6,0,0.3,meter_comp6,6);
meter_comp6 =  _<:attach( ba.linear2db:  hgroup("tabA",vgroup("[3]GR mb_ms_comp", hbargraph("[unit:db]", -6,0))));
multi_ms_comp6 = ms_enc : split3 : comp6 : join3 : ms_dec;

// Lookahead Limiter
limiter = co.limiter_lad_stereo(0, -10 : ba.db2linear, 0.001, 0.01, 0.05);





// metering
input_meter = hgroup("tabA", hgroup("[0]Input",vmeter)), hgroup("tabA", hgroup("[0]Input",vmeter));
output_meter = hgroup("tabA", hgroup("[9]Output",vmeter)), hgroup("tabA", hgroup("[9]Output",vmeter));
vmeter(x)       = attach(x, envelop(x) : vbargraph("[unit:dB]", -70, 0));
hmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:dB]", -50, 0));
dmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:db]", -12, 12));
gmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:db]", 0, 6));
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

diffN_cubic = diffN_meter(hgroup("tabA", vgroup("[5]GR cubic_clipper", gmeter)));
diffN_limiter = diffN_meter(hgroup("tabA", vgroup("[4]GR limiter", gmeter)));


// modified standard functions

limiter_lad_N(N, LD, ceiling, attack, hold, release) = 
      si.bus(N) <: par(i, N, @ (LD * ma.SR)), 
                   (scaling <: si.bus(N)) : ro.interleave(N, 2) : par(i, N, *)
      with {
           scaling = ceiling / max(amp_profile, ma.EPSILON) : min(1);
           amp_profile = par(i, N, abs) : maxN(N) : ba.peakholder(hold * ma.SR) :
               att_smooth(attack) : rel_smooth(release);
           att_smooth(time, in) = si.smooth(ba.tau2pole(time), in);
           rel_smooth(time, in) = an.peak_envelope(time, in);
           maxN(1) = _;
           maxN(2) = max;
           maxN(N) = max(maxN(N - 1));
      };