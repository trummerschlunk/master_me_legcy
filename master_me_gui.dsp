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
 * some building blocks by Julius Smith
 * a lot of help came from the faust community, especially sletz, magnetophone, dario sanphilippo, julius smith
*/
declare name      "master_me_gui";
declare author    "Klaus Scheuermann";
declare version   "2.0";
declare copyright "(C) 2021 Klaus Scheuermann";
import("stdfaust.lib");



// main
process(x1, x2) = x1,x2 : 
    input_meter :
    LUFS_in_meter :
    dc :
    ba.bypass2(checkbox("bypass all"), 
    hgroup("MASTER_ME", vgroup("[2]LEVELER", ba.bypass2(checkbox("bypass leveler"),LEVELER(max(abs(x1),abs(x2)))))) :     
    MB_MS_COMP :
    LIMITER :
    BRICKWALL ) :
    LUFS_out_meter:
    output_meter;



// simple gain function (stereo)
gain(x) = _ * (x :ba.db2linear) , _ * (x :ba.db2linear);



// dc filter (stereo)
dc = fi.dcblocker,fi.dcblocker;

//k-filter by Julius Smith
    highpass = fi.highpass(2, 40);
    boostDB = 4;
    boostFreqHz = 1430; // a little too high - they should give us this!
    highshelf = fi.high_shelf(boostDB, boostFreqHz); // Looks very close, but 1 kHz gain has to be nailed
    kfilter = highshelf : highpass;

// LEVELER
LEVELER(sc, x1, x2) = x1 * g * calc(sc), x2 * g * calc(sc) : post_gain with{
    // leveler headroom gain
    //g = hgroup("MASTER_ME", vgroup("[1]HEADROOM",vslider("gain[unit:dB]",20,0,30,1))) : si.smoo :ba.db2linear;
    g = 20 : ba.db2linear;
    
    // leveler calculation
    calc(sc) = sc * 6 * g : kfilter : (ma.tanh <: * : lp1p(tg) : sqrt) - 1 : abs : ba.linear2db *1.5 : meter_leveler : ba.db2linear 
    with {
        t= hslider("[3]speed", 0.02,0.01,0.1,0.01) ;
        tg = gate(sc) * t : hbargraph("[2]speed + gate",0,0.1) ; 
    };

    lp1p(cf, x) = +(x * (1 - b)) ~ (*(b) + init)
        with {
            init = 0.62 - 0.62';
            b = exp(-2 * ma.PI * cf / ma.SR);
        };

    gate(sc) = gate_gain_mono(g_thr, 0.01, 0.2, 0.1, abs(sc) ) with {
        g_thr = hslider("[4]leveler gate threshold[unit:dB]", -60,-90,0,1);
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


    //old filter
    old_filter = fi.highpass(1,180); 

    //post_gain
    post_gain = _ * g ,_ * g with {
        g =  hslider("[5]post gain[unit:dB]", 0,-10,+10,0.5) : ba.db2linear;
    };

    //metering
    meter_leveler = _ <: _, _+20 : attach(hbargraph("[1]gain[unit:dB]",-20,20));

    //variable t fpr  future use
    //brake(sc) = sc : an.abs_envelope_rect(1) ^(0.1)  : hgroup("tabA", vgroup("[2]GR Leveler", hbargraph("brake",0,1)));

};



//MULTIBAND MS COMPRESSOR
MB_MS_COMP = ms_enc : split3 : comp6 : join3 : ms_dec : post_gain with{

    // stereo to m/s encoder
    ms_enc = _*0.5,_*0.5 <: +, -;
    // m/s to stereo decoder
    ms_dec = _,_ <: +, -;
    // 3-band splitter stereo
    split3 = _,_ : fi.filterbank(3, (250,2500)), fi.filterbank(3, (250,2500)) : _,_,_,_,_,_;
    // 3-band joiner stereo
    join3 = (si.bus(3) :> _) , (si.bus(3) :> _);

    // 6ch FB compressor + mb_ms version
    comp6 = co.FBcompressor_N_chan(0.6,-13,0.02,0.5,6,0,0.3,meter_comp6,6);
    meter_comp6 =  _<:attach( ba.linear2db:  hgroup("MASTER_ME",vgroup("[3]MULTIBAND MID-SIDE COMPRESSOR", hbargraph("[1][unit:db]", -6,0))));

    //post_gain
    post_gain = _ * g ,_ * g with {
        g =  hgroup("MASTER_ME",vgroup("[3]MULTIBAND MID-SIDE COMPRESSOR", hslider("[9]post gain[unit:dB]", 0,-10,+10,0.5))) : ba.db2linear;
    };

};



// LIMITER
LIMITER = limiter_lad_stereo(limiter_lad_lookahead, limiter_lad_ceil, limiter_lad_attack, limiter_lad_hold, limiter_lad_release) : post_gain with{
    
    limiter_lad_lookahead = 0.01;
    limiter_lad_ceil = -6 : ba.db2linear;
    limiter_lad_attack = 0.01;
    limiter_lad_hold = 0.05;
    limiter_lad_release = 0.2;

    // LIMITER LAD STEREO
    limiter_lad_stereo(LD) = limiter_lad_N(2, LD);
    
    // LIMITER LAD N
    limiter_lad_N(N, LD, ceiling, attack, hold, release) = 
      si.bus(N) <: par(i, N, @ (LD * ma.SR)), 
                   (scaling <: si.bus(N)) : ro.interleave(N, 2) : par(i, N, *)
      with {
           scaling = ceiling / max(amp_profile, ma.EPSILON) : min(1) : meter_limiter_lad_N;
           amp_profile = par(i, N, abs) : maxN(N) : ba.peakholder(hold * ma.SR) :
               att_smooth(attack) : rel_smooth(release);
           att_smooth(time, in) = si.smooth(ba.tau2pole(time), in);
           rel_smooth(time, in) = an.peak_envelope(time, in);
           maxN(1) = _;
           maxN(2) = max;
           maxN(N) = max(maxN(N - 1));
      };

    //post_gain
    post_gain = _ * g ,_ * g with {
        g =  hgroup("MASTER_ME",hgroup("[7]LIMITER", vslider("[9]post gain[unit:dB]", 0,-10,+10,0.5))) : ba.db2linear;
    };

    // LIMITER metering
    meter_limiter_lad_N = _ <: attach(si.smoo : ba.linear2db : hgroup("MASTER_ME",hgroup("[7]LIMITER",vbargraph("[8][unit:dB]GR",-12,0))));
};



BRICKWALL = limiter_lad_stereo(limiter_lad_lookahead, limiter_lad_ceil, limiter_lad_attack, limiter_lad_hold, limiter_lad_release) with{
    
    twopi = 2 * ma.PI;

    limiter_lad_lookahead = 0.01;
    limiter_lad_ceil = -1 : ba.db2linear;
    limiter_lad_attack = .01 / twopi;
    limiter_lad_hold = .1;
    limiter_lad_release = 1 / twopi;

    // LIMITER LAD STEREO
    limiter_lad_stereo(LD) = limiter_lad_N(2, LD);
    
    // LIMITER LAD N
    limiter_lad_N(N, LD, ceiling, attack, hold, release) = 
      si.bus(N) <: par(i, N, @ (LD * ma.SR)), 
                   (scaling <: si.bus(N)) : ro.interleave(N, 2) : par(i, N, *)
      with {
           scaling = ceiling / max(amp_profile, ma.EPSILON) : min(1) : meter_limiter_lad_N;
           amp_profile = par(i, N, abs) : maxN(N) : ba.peakholder(hold * ma.SR) :
               att_smooth(attack) : rel_smooth(release);
           att_smooth(time, in) = si.smooth(ba.tau2pole(time), in);
           rel_smooth(time, in) = an.peak_envelope(time, in);
           maxN(1) = _;
           maxN(2) = max;
           maxN(N) = max(maxN(N - 1));
      };

    // BRICKWALL metering
    meter_limiter_lad_N = _ <: attach(si.smoo : ba.linear2db : hgroup("MASTER_ME",hgroup("[8]BRICKWALL",vbargraph("[8][unit:dB]GR",-12,0))));
};



// METERING
input_meter = hgroup("MASTER_ME", hgroup("[0]INPUT",vmeter)), hgroup("MASTER_ME", hgroup("[0]INPUT",vmeter));
output_meter = hgroup("MASTER_ME", hgroup("[9]OUTPUT",vmeter)), hgroup("MASTER_ME", hgroup("[9]OUTPUT",vmeter));

vmeter(x)       = attach(x, envelop(x) : vbargraph("[unit:dB]", -70, 0));
hmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:dB]", -50, 0));

envelop         = abs : max(ba.db2linear(-70)) : ba.linear2db : min(10)  : max ~ -(40.0/ma.SR);


// LUFS Meter
// Power sum:
Tg = 0.4; // spec calls for 75% overlap of successive rectangular windows - we're overlapping MUCH more (sliding window)
//zi = an.ms_envelope_rect(Tg); // mean square: average power = energy/Tg = integral of squared signal / Tg

//envelope via lp by dario
lp1p(cf, x) = fi.pole(b, x * (1 - b)) with {
    b = exp(-2 * ma.PI * cf / ma.SR);
};

zi_lp(x) = lp1p(1 / Tg, x * x);

// Gain vector Gv = (GL,GR,GC,GLs,GRs):
N = 5;
Gv = (1, 1, 1, 1.41, 1.41); // left GL(-30deg), right GR (30), center GC(0), left surround GLs(-110), right surr. GRs(110)
G(i) = *(ba.take(i+1,Gv));
Lk(i) = kfilter : zi_lp : G(i); // one channel, before summing and before taking dB and offsetting
LkDB(i) = Lk(i) : 10 * log10 : -(0.691); // Use this for a mono input signal

// Five-channel surround input:
Lk5 = par(i,5,Lk(i)) :> 10 * log10 : -(0.691);
// stereo
Lk2 = Lk(0),Lk(2) :> 10 * log10 : -(0.691);

//process(x,y) = x,y <: (_,_), attach(x, (Lk2 : vbargraph("LUFS",-90,0))) : _,_,_ ;

LUFS_in_meter(x,y) = x,y <: x, attach(y, (Lk2 : hgroup("MASTER_ME", hgroup("[0]INPUT",vbargraph("LUFS",-90,0))))) : _,_;
LUFS_out_meter(x,y) = x,y <: x, attach(y, (Lk2 : hgroup("MASTER_ME", hgroup("[9]OUTPUT",vbargraph("LUFS",-90,0))))) : _,_;