/* automatic mastering processor for live streaming events.*/
/* originally developed for the ccrma 'Quarantine Sessions'*/
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
/* some building blocks where taken from or inspired by Dario Sanfilippo <sanfilippo.dario at gmail dot com>
 * some building blocks by Stéphane Letz
 * some building blocks by Julius Smith
 * some building blocks by Yann Orlarey
 * a lot of help came from the faust community, especially sletz, magnetophone, Dario Sanphilippo, Julius Smith, Juan Carlos Blancas, Yann Orlarey
*/
declare name      "master_me_gui";
declare author    "Klaus Scheuermann";
declare version   "2.0";
declare copyright "(C) 2021 Klaus Scheuermann";
import("stdfaust.lib");

// init values

Nch = 2; //number of channels (must be even!)

init_noisegate_threshold = -70;

init_leveler_target = -18;
init_leveler_maxboost = 55;
init_leveler_maxcut = 55;
init_leveler_gatethreshold = -50;
init_leveler_speed = .095;

init_mbmscomp_thresh = -10;

init_comp_thresh = -22;
init_comp_thresh_mult = 1;
init_comp_thresh_tilt = -4;
init_comp_xo1 = 150;
init_comp_xo2 = 500;
init_comp_xo3 = 2000;
init_comp_xo4 = 6000;
init_comp_makeup = 3;

init_limiter_lad_ceil = -5;
init_limiter_postgain = 3;

init_brickwall_ceiling = -3;




// main
process = 
    
    ba.bypass2(checkbox("bypass all"),

    si.bus(Nch) : 
   
    hgroup("MASTER_ME", hgroup("[0]INPUT",peak_meter(Nch))) :
    
    hgroup("MASTER_ME", hgroup("[1]STEREO CORRECT",correlate_meter)) :
    hgroup("MASTER_ME", hgroup("[1]STEREO CORRECT",correlate_correct_bp)) :
    
    // hgroup("MASTER_ME", hgroup("[0]INPUT",lufs_any(Nch))) :

    dc_filter(Nch) :

    // hgroup("MASTER_ME", hgroup("[1.5]NOISEGATE",noisegate(Nch))):
    hgroup("MASTER_ME", hgroup("[2]LEVELER",leveler(Nch))) :
    // hgroup("MASTER_ME", vgroup("[3]MULTIBAND MID-SIDE COMPRESSOR", mbmscomp(Nch))) :
    // hgroup("MASTER_ME", vgroup("[3]MULTIBAND COMPRESSOR", mbcomp(Nch))) :
    hgroup("MASTER_ME", hgroup("[3]5-BAND COMPRESSOR", comp5st)) :
    hgroup("MASTER_ME", hgroup("[7]LIMITER", limiter(Nch))) :
    hgroup("MASTER_ME", hgroup("[8]BRICKWALL",brickwall(Nch))) :
    
    hgroup("MASTER_ME", hgroup("[9]OUTPUT",lufs_any(Nch))) :
    hgroup("MASTER_ME", hgroup("[9]OUTPUT",peak_meter(Nch))) :
    
    
    si.bus(Nch)
    ) // bypass end
;


// DC FILTER
dc_filter(N) = par(i,N,fi.dcblocker);

// NOISE GATE
noisegate(N) = gate_any(N,noisegate_thresh,noisegate_attack,noisegate_hold,noisegate_release) with {
    noisegate_thresh = vslider("[0]threshold",init_noisegate_threshold, -95, 0, 1);
    noisegate_attack = 0.01;
    noisegate_hold = 1;
    noisegate_release = 2;

    gate_any(N,thresh,att,hold,rel) = B <: B, (B :> ggm : vbargraph("[2]gate level",0,1) <: B) : ro.interleave(N,2) : par(i,N,*) 
    with { 
        B = si.bus(N); 
        ggm = gate_gain_mono(thresh,att,hold,rel);
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


// LEVELER
leveler(N) = B <: B, (B :> _ <: _,_ : calc : _ <: B) : ro.interleave(N,2) : par(i,N,*)
    with {

    B = si.bus(N);
    
    calc(mono,sc) = (mono : Lk : vbargraph("[1]in LUFS S",-40,0) : (target - _) : lp1p(leveler_speed_gated(sc)) : limit(limit_neg,limit_pos) : vbargraph("[2]gain",-50,50) : ba.db2linear) , sc : _,!;

    target = vslider("[3]target LUFS[unit:dB]", init_leveler_target,-50,0,1);
    
    limit_pos = vslider("[5]max boost", init_leveler_maxboost, 0, 60, 1);
    limit_neg = vslider("[6]max cut", init_leveler_maxcut, 0, 60, 1) : ma.neg;
    limit(lo,hi) = min(hi) : max(lo); 

    leveler_speed = vslider("[4]speed", init_leveler_speed, .005, 0.15, .005);
    leveler_speed_gated(sc) = (gate_gain_mono(leveler_gate_thresh,0.1,0,0.1,abs(sc)) <: attach(_, (1-_) : vbargraph("[7]leveler gate",0,1))) : _ * leveler_speed;
    leveler_gate_thresh = vslider("[8]lev gate thresh[unit:dB]", init_leveler_gatethreshold,-90,0,1);

    // from library:
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

// MULTIBAND MS COMPRESSOR
mbmscomp(N) = par(i,N /2, ms_enc : split3) : comp_Nch(N) : par(i,N /2, join3 : ms_dec) : post_gain with{

    // stereo to m/s encoder
    ms_enc = _*0.5,_*0.5 <: +, -;
    // m/s to stereo decoder
    ms_dec = _,_ <: +, -;
    // 3-band splitter stereo
    split3 = _,_ : par(i,2,fi.filterbank(3, (xo1,xo2))) : _,_,_,_,_,_ with {
        xo1 = 250;
        xo2 = 2500;
    };
    // 3-band joiner stereo
    join3 = (si.bus(3) :> _) , (si.bus(3) :> _);

    // Nch FB compressor
    comp_Nch(N) = co.FBcompressor_N_chan(0.6,init_mbmscomp_thresh,0.02,0.5,6,0,0.3,meter_comp,N *3);
    meter_comp =  _<:attach( ba.linear2db :  hbargraph("[1][unit:db]", -6,0));

    //post_gain
    post_gain = par(i,N,_ * g) with {
        g =  hslider("[9]post gain[unit:dB]", 0,-10,+10,0.5) : ba.db2linear;
    };

};

// MULTIBAND COMPRESSOR
mbcomp(N) = par(i,N /2, split3) : comp_Nch(N) : par(i,N /2, join3 ) : post_gain with{

    // stereo to m/s encoder
    ms_enc = _*0.5,_*0.5 <: +, -;
    // m/s to stereo decoder
    ms_dec = _,_ <: +, -;
    // 3-band splitter stereo
    split3 = _,_ : par(i,2,fi.filterbank(3, (xo1,xo2))) : _,_,_,_,_,_ with {
        xo1 = 250;
        xo2 = 2500;
    };
    // 3-band joiner stereo
    join3 = (si.bus(3) :> _) , (si.bus(3) :> _);

    // Nch FB compressor
    comp_Nch(N) = co.FBcompressor_N_chan(0.6,init_mbmscomp_thresh,0.02,0.5,6,0,0.3,meter_comp,N *3);
    meter_comp =  _<:attach( ba.linear2db :  hbargraph("[1][unit:db]", -6,0));

    //post_gain
    post_gain = par(i,N,_ * g) with {
        g =  hslider("[9]post gain[unit:dB]", 0,-10,+10,0.5) : ba.db2linear;
    };

};



// 5 BAND STEREO COMPRESSOR
comp5st = _,_ : split5 : route(10,10,    1,1,  2,3,  3,5,  4,7,  5,9,  6,2,  7,4,  8,6,  9,8,  10,10) : comp_hi,comp_himid,comp_mid,comp_lomid,comp_lo :> _,_ : makeup(Nch) with {
    
    split5 = _,_ : par(i,2,fi.filterbank(3, (xo1,xo2,xo3,xo4)))  : si.bus(10)  with {
        xo1 = vslider("xo1",init_comp_xo1,50,350,1);
        xo2 = vslider("xo2",init_comp_xo2,351,1000,1);
        xo3 = vslider("xo3",init_comp_xo3,1001,4000,1);
        xo4 = vslider("xo4",init_comp_xo4,4001,10000,1);
    };

    join4 = (si.bus(5) :> _) , (si.bus(5) :> _);

    comp_strength = 0.6;
    comp_att = 0.02;
    comp_rel = 0.05;
    comp_knee = 6;
    comp_prepost = 0;

    comp_thresh = vslider("[1]threshold (db)",init_comp_thresh,-60,0,1);
    comp_thresh_tilt = vslider("[2]threshold tilt",init_comp_thresh_tilt,-6,6,0.5);

    comp_lo    = _,_ : co.FBcompressor_N_chan(comp_strength, comp_thresh - comp_thresh_tilt, comp_att, comp_rel, comp_knee, comp_prepost, 1, meter_comp,2) with {
        meter_comp =  _<:attach( ba.linear2db : abs : vbargraph("[4]GR lo[unit:db]", 0,12));
    };
    comp_lomid = _,_ : co.FBcompressor_N_chan(comp_strength, comp_thresh - comp_thresh_tilt / 2, comp_att, comp_rel, comp_knee, comp_prepost, 1, meter_comp,2) with {
        meter_comp =  _<:attach( ba.linear2db : abs : vbargraph("[5]GR lo-mid[unit:db]", 0,12));
    };
    comp_mid   = _,_ : co.FBcompressor_N_chan(comp_strength, comp_thresh, comp_att, comp_rel, comp_knee, comp_prepost, 1, meter_comp,2) with {
        meter_comp =  _<:attach( ba.linear2db : abs : vbargraph("[6]GR mid[unit:db]", 0,12));
    };
    comp_himid = _,_ : co.FBcompressor_N_chan(comp_strength, comp_thresh + comp_thresh_tilt / 2, comp_att, comp_rel, comp_knee, comp_prepost, 1, meter_comp,2) with {
        meter_comp =  _<:attach( ba.linear2db : abs : vbargraph("[7]GR hi-mid[unit:db]", 0,12));
    };
    comp_hi    = _,_ : co.FBcompressor_N_chan(comp_strength, comp_thresh + comp_thresh_tilt, comp_att, comp_rel, comp_knee, comp_prepost, 1, meter_comp,2) with {
        meter_comp =  _<:attach( ba.linear2db : abs : vbargraph("[8]GR hi[unit:db]", 0,12));
    };


    //post_gain
    makeup(n) = par(i,n,_ * g) with {
        g =  vslider("[9]makeup[unit:dB]",init_comp_makeup,-10,+10,0.5) : ba.db2linear;
    };

    

    meter_comp =  _<:attach( ba.linear2db :  vbargraph("[1][unit:db]", -6,0));
};

// LIMITER
limiter(N) = limiter_lad_N(N,limiter_lad_lookahead, init_limiter_lad_ceil : ba.db2linear, limiter_lad_attack, limiter_lad_hold, limiter_lad_release) : post_gain with{
    
    limiter_lad_lookahead = 0.01;
    limiter_lad_attack = 0.01;
    limiter_lad_hold = 0.05;
    limiter_lad_release = 0.2;

    // lookahead limiter (N-channel)
    limiter_lad_N(N, LD, ceiling, attack, hold, release) = 
        si.bus(N) <: par(i, N, @ (LD * ma.SR)), 
            (scaling <: si.bus(N)) : ro.interleave(N, 2) : par(i, N, *)
        with {
            scaling = ceiling / max(amp_profile, ma.EPSILON) : min(1) : meter_limiter_lad_N;
            amp_profile = par(i, N, abs) : maxN(N) : ba.peakholder(hold * ma.SR) : att_smooth(attack) : rel_smooth(release);
            att_smooth(time, in) = si.smooth(ba.tau2pole(time), in);
            rel_smooth(time, in) = an.peak_envelope(time, in);
            maxN(1) = _;
            maxN(2) = max;
            maxN(N) = max(maxN(N - 1));
        };

    // post_gain
    post_gain = par(i,Nch,_ * g) with {
        g =  vslider("[9]post gain[unit:dB]", init_limiter_postgain,-10,+10,0.5) : ba.db2linear;
    };

    // metering
    //meter_limiter_lad_N = _ <: attach(ba.linear2db : vbargraph("[8][unit:dB]GR",-12,0));
    meter_limiter_lad_N = _ <: attach(ba.linear2db : abs : vbargraph("[8][unit:dB]GR",0,12));
};


// BRICKWALL
brickwall(N) = limiter_lad_N(N, limiter_lad_lookahead, limiter_lad_ceil, limiter_lad_attack, limiter_lad_hold, limiter_lad_release)
    with{
    
    twopi = 2 * ma.PI;

    limiter_lad_lookahead = 0.01;
    limiter_lad_ceil = init_brickwall_ceiling : ba.db2linear;
    limiter_lad_attack = .01 / twopi;
    limiter_lad_hold = .1;
    limiter_lad_release = 1 / twopi;
    
    // lookahead limiter (N-channel)
    limiter_lad_N(N, LD, ceiling, attack, hold, release) = 
        si.bus(N) <: par(i, N, @ (LD * ma.SR)), 
            (scaling <: si.bus(N)) : ro.interleave(N, 2) : par(i, N, *)
        with {
            scaling = ceiling / max(amp_profile, ma.EPSILON) : min(1) : meter_limiter_lad_N;
            amp_profile = par(i, N, abs) : maxN(N) : ba.peakholder(hold * ma.SR) : att_smooth(attack) : rel_smooth(release);
            att_smooth(time, in) = si.smooth(ba.tau2pole(time), in);
            rel_smooth(time, in) = an.peak_envelope(time, in);
            maxN(1) = _;
            maxN(2) = max;
            maxN(N) = max(maxN(N - 1));
        };

    // metering
    meter_limiter_lad_N = _ <: attach(ba.linear2db : abs : vbargraph("[8][unit:dB]GR",0,12));
};

// METERING
peak_meter(N) = par(i, N, (_ <: attach(_, envelop : vbargraph("[unit:dB]CH %i", -70, 0)))) with{
    
    vmeter(x) = attach(x, envelop(x) : vbargraph("[unit:dB]", -70, 0));
    envelop = abs : max(ba.db2linear(-70)) : ba.linear2db : min(10) : max ~ -(40.0/ma.SR);
};


// LUFS metering (without channel weighting)
Tg = 3; // 3 second window for 'short-term' measurement
// zi = an.ms_envelope_rect(Tg); // mean square: average power = energy/Tg = integral of squared signal / Tg

//k-filter by Julius Smith
highpass = fi.highpass(2, 80);
boostDB = 4;
boostFreqHz = 1430; // a little too high - they should give us this!
highshelf = fi.high_shelf(boostDB, boostFreqHz); // Looks very close, but 1 kHz gain has to be nailed
kfilter = highshelf : highpass;

//envelope via lp by Dario Sanphilippo
lp1p(cf, x) = fi.pole(b, x * (1 - b)) with {
    b = exp(-2 * ma.PI * cf / ma.SR);
};
zi_lp(x) = lp1p(1 / Tg, x * x);

// one channel
Lk = kfilter: zi_lp : 10 * log10(max(ma.EPSILON)) : -(0.691);

// N-channel
LkN = par(i,Nch,kfilter : zi_lp) :> 10 * log10(max(ma.EPSILON)) : -(0.691);

// N-channel by Yann Orlarey
lufs_any(N) = B <: B, (B :> Lk : vbargraph("LUFS S",-40,0)) : si.bus(N-1), attach(_,_)
    with { 
        B = si.bus(N); 
        
    };


// correlation meter
correlate_meter(x,y) = x,y <: x , attach(y, (corr(t) : vbargraph("correlation",-1,1))) : _,_ with {
    t = .2; // averaging period in seconds
    
    avg(t, x) = fi.pole(p, (1 - p) * x) // 1-pole lowpass as average
        with {
            p = exp((((-2.0 * ma.PI) / t) / ma.SR));
        };
    var(t, x) = avg(t, (x - avg(t, x)) ^ 2); // variance
    sd(t, x) = sqrt(var(t, x)); // standard deviation
    cov(t, x1, x2) = avg(t, (x1 - avg(t, x1)) * (x2 - avg(t, x2))); // covariance
    corr(t, x1, x2) = cov(t, x1, x2) / max(ma.EPSILON, (sd(t, x1) * sd(t, x2))); // correlation
};

// stereo correction based on correlation
correlate_correct(l,r) = out_pos1, out_neg1, out_0, out_pos, out_neg :> _,_ with {
    
    t = .2; // averaging period in seconds
    
    avg(t, x) = fi.pole(p, (1 - p) * x) // 1-pole lowpass as average
        with {
            p = exp((((-2.0 * ma.PI) / t) / ma.SR));
        };
    var(t, x) = avg(t, (x - avg(t, x)) ^ 2); // variance
    sd(t, x) = sqrt(var(t, x)); // standard deviation
    cov(t, x1, x2) = avg(t, (x1 - avg(t, x1)) * (x2 - avg(t, x2))); // covariance
    corr(t, x1, x2) = cov(t, x1, x2) / max(ma.EPSILON, (sd(t, x1) * sd(t, x2))); // correlation
    
    
    th =.0001;
    corr_pos1 = avg(t, (corr(t,l,r) > (1-th))) : smoothing : vbargraph("[5]1",0,1);
    corr_neg1 = avg(t, corr(t,l,r) < (-1+th)) : smoothing : vbargraph("[9]-1",0,1);
    corr_0 = avg(t, ((corr(t,l,r) < th) & (corr(t,l,r) > (0-th)))) : smoothing: vbargraph("[7]0",0,1);
    corr_pos = avg(t, ((corr(t,l,r) > (0+th)) & (corr(t,l,r) < (1-th)))) : smoothing: vbargraph("[6]>0,<1",0,1);
    corr_neg = avg(t, ((corr(t,l,r) > (-1+th)) & (corr(t,l,r) < (0-th)))) : smoothing: vbargraph("[8]>-1,<0",0,1);

    smoothing = lp1p(2) ;
    corr_meter = vbargraph("[9]",0,1);

    out_pos1 = ((l * corr_pos1 + r * corr_pos1) /2) , ((l * corr_pos1 + r * corr_pos1) /2);
    out_neg1 = ((l * corr_neg1 + (-r) * corr_neg1) /2) , ((l * corr_neg1 + (-r) * corr_neg1) /2);
    out_0 = (l * corr_0 + r * corr_0) , (l * corr_0 + r * corr_0);
    out_pos = l * corr_pos , r * corr_pos;
    //out_neg = l * corr_neg , (0-(r * corr_neg));
    out_neg = l * corr_neg , r * corr_neg;
};

// stereo correction bypass checkbox
correlate_correct_bp = ba.bypass2(checkbox("bypass"), correlate_correct);