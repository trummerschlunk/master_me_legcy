################################################################################
#							FaustWeb OSX script
#  The behaviour of this Makefile will only be correct if
#  only one .dsp file exists in the folder
################################################################################

faustfile	?= $(wildcard *.dsp)

binary.zip : $(faustfile)
	osx faust2faustvst $(faustfile) $(OPT)
	zip -r binary.zip *

src.cpp : $(faustfile)
	faust -i -a faustvst.cpp $(faustfile) -o src.cpp
