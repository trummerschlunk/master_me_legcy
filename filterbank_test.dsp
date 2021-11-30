import("stdfaust.lib");

M = 2;
ftop = 20000;
N = 20;

compN = co.RMS_FBFFcompressor_N_chan(strength,thresh,att,rel,knee,prePost,link,FBFF,meter,N) with{
    strength = 0.2;
    thresh = -30;
    att = 0.01;
    rel = 0.1;
    knee = 1;
    prePost = 0;
    link = 0;
    FBFF = 0.5;
    meter =  _<:attach( ba.linear2db : hgroup("hurz", vbargraph("[1][unit:db]", -6,0)));
};

process = _ : fi.mth_octave_filterbank(3,M,ftop,N) : compN : par(i,N,_) :> _ <: _,_;