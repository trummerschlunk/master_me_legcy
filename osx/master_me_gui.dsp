declare filename "master_me_gui.dsp"; declare name "master_me_gui"; /* automatic mastering chain for the ccrma 'Quarantine Sessions'*/
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
        input_meter : dc : 
        ba.bypass2(checkbox("bypass all"), 
        leveler_stereo(x1+x2) : multi_ms_comp6 : gain(2) : diffN_limiter(limiter) : diffN_cubic(cubic_st(6))
        ) : gain(5.9) : output_meter;

// headroom gain (stereo)
g = hgroup("tabA", vgroup("[1]Headroom",vslider("gain[unit:dB]",18,0,30,1))) : si.smoo :ba.db2linear;

// simple gain function (stereo)
gain(x) = _ * (x :ba.db2linear) , _ * (x :ba.db2linear);

// dc filter (stereo)
dc = fi.dcblocker,fi.dcblocker;

// leveler
leveler_stereo(sc, x1, x2) = x1 * g * calc(sc), x2 * g * calc(sc);

calc(sc) = sc * 3 * g : fi.highpass(2,20) : (ma.tanh <: * : lp1p(tg) : sqrt) - 1 : abs  : ba.linear2db: hgroup("tabA", vgroup("[2]Leveler", hbargraph("[1]gain reduction[unit:dB]",-24,0))) : ba.db2linear 
with {
    t= hgroup("tabA", vgroup("[2]Leveler",hslider("[3]leveler speed", 0.02,0.01,0.1,0.01))) ;
    gate_thresh = hgroup("tabA", vgroup("[2]Leveler",hslider("gate threshold[unit:dB]", -40,-90,0,1))) :ba.db2linear;
    tg = ba.if(sc *g : an.abs_envelope_rect(0.1) <= gate_thresh, 0, t) : hgroup("tabA", vgroup("[2]Leveler", hbargraph("[2]leveler speed with gate",0,0.1))) ; 
};

lp1p(cf, x) = +(x * (1 - b)) ~ (*(b) + init)
    with {
        init = .5 - .5';
        b = exp(-2 * ma.PI * cf / ma.SR);
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
comp6 = co.FBcompressor_N_chan(0.6,-17,0.02,0.5,6,0,0.3,meter_comp6,6);
meter_comp6 =  _<:attach( ba.linear2db:  hgroup("tabA",vgroup("[3]GR mb_ms_comp", hbargraph("[unit:db]", -6,0))));
multi_ms_comp6 = ms_enc : split3 : comp6 : join3 : ms_dec;

// Lookahead Limiter
limiter = co.limiter_lad_stereo(0, -10 : ba.db2linear, 0.001, 0.01, 0.05);

// cubic nonlinear distortion by Dario Sanfilippo
cubic(x) = select3(cond, -2/3, x-(x*x*x/3), 2/3)
    with {
        cond = ((x : >(-1)),
                (x : <(1)) : &),
                (x : >=(1))*2 :> _;
    };
cubic_st(d) = _* (d : ba.db2linear) ,_* (d : ba.db2linear) : cubic, cubic : _/(d : ba.db2linear),_/(d : ba.db2linear);





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
