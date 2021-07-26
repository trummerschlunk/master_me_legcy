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
 * a lot of help came from the faust community, especially sletz, magnetophone, dario sanphilippo, julius smith, juan carlos blancas
*/
declare name      "master_me_gui";
declare author    "Klaus Scheuermann";
declare version   "2.0";
declare copyright "(C) 2021 Klaus Scheuermann";
import("stdfaust.lib");

// init values

Nch = 2; //number of channels, must be even, STILL ONLY WORKS IN STEREO WITH Nch = 2

init_noisegate_threshold = -70;

init_leveler_target = -18;
init_leveler_maxboost = 3;
init_leveler_maxcut = 3;
init_leveler_gatethreshold = -34;
init_leveler_speed = .005;

init_mbmscomp_thresh = -10;

init_limiter_lad_ceil = -2;

init_BRICKWALL_ceiling = -0.7;

// main
process(x1, x2) = x1,x2 : 
    input_meter :
    LUFS_in_meter :
    ba.bypass2(checkbox("bypass all"),
    dc :
    hgroup("MASTER_ME", vgroup("[1.5]NOISEGATE",NOISEGATE)):
    hgroup("MASTER_ME", vgroup("[2]LEVELER",LEVELER)) :
    MB_MS_COMP :
    LIMITER :
    BRICKWALL ) :
    LUFS_out_meter :
    output_meter
    ;


// simple gain function (N-channel)
gain(x) = par(i,Nch,_ * (x :ba.db2linear));

// dc filter (N-CHannel)
dc = par(i,Nch,fi.dcblocker);

// Noise Gate (N-channel)
NOISEGATE = gate_Nch(noisegate_thresh,noisegate_attack,noisegate_hold,noisegate_release) with {
    noisegate_thresh = vslider("[0]threshold",init_noisegate_threshold, -95, 0, 1);
    noisegate_attack = 0.01;
    noisegate_hold = 1;
    noisegate_release = 2;

    gate_Nch(thresh,att,hold,rel,x,y) = par(i,Nch,ggm*x) with {
            ggm = gate_gain_mono(thresh,att,hold,rel,abs(x)+abs(y)) : vbargraph("[2]gate level",0,1);
        };

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
};
//k-filter by Julius Smith
highpass = fi.highpass(2, 40);
boostDB = 4;
boostFreqHz = 1430; // a little too high - they should give us this!
highshelf = fi.high_shelf(boostDB, boostFreqHz); // Looks very close, but 1 kHz gain has to be nailed
kfilter = highshelf : highpass;

// LEVELER
LEVELER(l,r) = l * (difference(l,r)  : ba.db2linear), r * (difference(l,r) : ba.db2linear) with{
    
    target = hslider("[3]target loudness (LUFS)[unit:dB]", init_leveler_target,-50,0,1);
    difference(l,r) = (target - (LkN(l,r)  :  hbargraph("[1]input (LUFS S)",-40,0))) : lp1p(leveler_speed_gated) : limit(limit_neg,limit_pos) : hbargraph("[2]gain",-10,10);

    limit_pos = hslider("[4]maximum boost (db)", init_leveler_maxboost, 0, 10, 1);
    limit_neg = hslider("[5]maximum cut (db)", init_leveler_maxcut, 0, 10, 1) : ma.neg;
    limit(lo,hi) = min(hi) : max(lo); 

    leveler_speed = hslider("[7]leveler speed", init_leveler_speed, .005, 0.1, .005);
    //leveler_speed_gated = ba.if(Lk2(l,r) <= leveler_gate_thresh, 0, leveler_speed) : hbargraph("[6]gated leveler speed",0,0.2) ;
    leveler_speed_gated = (gate_gain_mono(leveler_gate_thresh,0.1,0,0.1,abs(l)+abs(r)) : hbargraph("[6]leveler gate",0,0.2)) * leveler_speed;
    leveler_gate_thresh = hslider("[8]leveler gate threshold (db)[unit:dB]", init_leveler_gatethreshold,-90,0,1);


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
    
};

//MULTIBAND MS COMPRESSOR
//MB_MS_COMP = ms_enc : split3 : comp6 : join3 : ms_dec : post_gain with{
MB_MS_COMP = par(i,Nch /2, ms_enc : split3 : comp6 : join3 : ms_dec) : post_gain with{

    // stereo to m/s encoder
    ms_enc = _*0.5,_*0.5 <: +, -;
    // m/s to stereo decoder
    ms_dec = _,_ <: +, -;
    // 3-band splitter stereo
    split3 = _,_ : fi.filterbank(3, (250,2500)), fi.filterbank(3, (250,2500)) : _,_,_,_,_,_;
    // 3-band joiner stereo
    join3 = (si.bus(3) :> _) , (si.bus(3) :> _);

    // 6ch FB compressor + mb_ms version
    comp6 = co.FBcompressor_N_chan(0.6,init_mbmscomp_thresh,0.02,0.5,6,0,0.3,meter_comp6,6);
    meter_comp6 =  _<:attach( ba.linear2db:  hgroup("MASTER_ME",vgroup("[3]MULTIBAND MID-SIDE COMPRESSOR", hbargraph("[1][unit:db]", -6,0))));

    //post_gain
    post_gain = par(i,Nch,_ * g) with {
        g =  hgroup("MASTER_ME",vgroup("[3]MULTIBAND MID-SIDE COMPRESSOR", hslider("[9]post gain[unit:dB]", 0,-10,+10,0.5))) : ba.db2linear;
    };

};

// LIMITER
LIMITER = limiter_lad_Nch(limiter_lad_lookahead, init_limiter_lad_ceil : ba.db2linear, limiter_lad_attack, limiter_lad_hold, limiter_lad_release) : post_gain with{
    
    limiter_lad_lookahead = 0.01;
    limiter_lad_attack = 0.01;
    limiter_lad_hold = 0.05;
    limiter_lad_release = 0.2;

    // LIMITER LAD STEREO
    limiter_lad_Nch(LD) = limiter_lad_N(Nch, LD);
    
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
    post_gain = par(i,Nch,_ * g) with {
        g =  hgroup("MASTER_ME",hgroup("[7]LIMITER", vslider("[9]post gain[unit:dB]", 0,-10,+10,0.5))) : ba.db2linear;
    };

    // LIMITER metering
    meter_limiter_lad_N = _ <: attach(ba.linear2db : hgroup("MASTER_ME",hgroup("[7]LIMITER",vbargraph("[8][unit:dB]GR",-12,0))));
};

BRICKWALL = limiter_lad_Nch(limiter_lad_lookahead, limiter_lad_ceil, limiter_lad_attack, limiter_lad_hold, limiter_lad_release) with{
    
    twopi = 2 * ma.PI;

    limiter_lad_lookahead = 0.01;
    limiter_lad_ceil = init_BRICKWALL_ceiling : ba.db2linear;
    limiter_lad_attack = .01 / twopi;
    limiter_lad_hold = .1;
    limiter_lad_release = 1 / twopi;

    // LIMITER LAD STEREO
    limiter_lad_Nch(LD) = limiter_lad_N(Nch, LD);
    
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
    meter_limiter_lad_N = _ <: attach(ba.linear2db : hgroup("MASTER_ME",hgroup("[8]BRICKWALL",vbargraph("[8][unit:dB]GR",-12,0))));
};

// METERING
input_meter = par(i, Nch, hgroup("MASTER_ME", hgroup("[0]INPUT",vmeter)));
output_meter = par(i, Nch, hgroup("MASTER_ME", hgroup("[9]OUTPUT",vmeter)));

vmeter(x)       = attach(x, envelop(x) : vbargraph("[unit:dB]", -70, 0));
hmeter(x)       = attach(x, envelop(x) : hbargraph("[unit:dB]", -50, 0));

envelop         = abs : max(ba.db2linear(-70)) : ba.linear2db : min(10)  : max ~ -(40.0/ma.SR);


// LUFS Metering
Tg = 3; // 3 second window for 'short-term' measurement
zi = an.ms_envelope_rect(Tg); // mean square: average power = energy/Tg = integral of squared signal / Tg

//envelope via lp by dario
lp1p(cf, x) = fi.pole(b, x * (1 - b)) with {
    b = exp(-2 * ma.PI * cf / ma.SR);
};
zi_lp(x) = lp1p(1 / Tg, x * x);

// Gain vector Gv = (GL,GR,GC,GLs,GRs):
N = 5;
//Gv = (1, 1, 1, 1.41, 1.41); // left GL(-30deg), right GR (30), center GC(0), left surround GLs(-110), right surr. GRs(110)
// G(i) = *(ba.take(i+1,Gv));
// Lk(i) = kfilter : zi_lp : G(i); // one channel, before summing and before taking dB and offsetting
Lk(i) = kfilter : zi_lp ; // one channel, no weighting
LkDB(i) = Lk(i) : 10 * log10(max(ma.EPSILON)) : -(0.691); // Use this for a mono input signal

// N-channel input:
LkN = par(i,Nch,Lk(i)) :> 10 * log10(max(ma.EPSILON)) : -(0.691);
// Five-channel surround input:
Lk5 = par(i,5,Lk(i)) :> 10 * log10(max(ma.EPSILON)) : -(0.691);
// Two -channel stereo input:
Lk2 = Lk(0),Lk(2) :> 10 * log10(max(ma.EPSILON)) : -(0.691);

LUFS_in_meter(x,y) = x,y <: x, attach(y, (LkN : hgroup("MASTER_ME", hgroup("[0]INPUT",vbargraph("LUFS S",-40,0))))) : _,_;
LUFS_out_meter(x,y) = x,y <: x, attach(y, (LkN : hgroup("MASTER_ME", hgroup("[9]OUTPUT",vbargraph("LUFS S",-40,0))))) : _,_;