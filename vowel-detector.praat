# vowel-detector
# --------------
# 
# Finds onsets and offsets of vowel-like segments in sound files based
# on the its energy profile. This is a complete rewrite of the
# BeatExtractor script coded by P. A. Barbosa, in turn based on
# Fred Cummins' algorithm described in the following reference.  
#
# Cummins, F., and Port, R. (1998). Rhythmic constraints on stress
#   timing in English. _Journal of Phonetics_, 26, 145–171.
#
# Pablo Arantes <pabloarantes@protonmail.com>
#
# = Version =
# [2.0] - 2021-01-16
# See CHANGELOG.md for a complete version history.
#
# Copyright (C) 2014-2021  Pablo Arantes
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

form Parameters specification
	comment "Single file": user will be prompted to select a sound file.
	comment "Multiple files": user has to provide a folder containing sound files.
	optionmenu Mode: 1
		option Single file 
		option Multiple file
	comment Directory where the sound files are ("Multiple files" mode):
	sentence Sound_files /home/paran/code/praat/beat_extractor/
	word Sound_extension .wav
	optionmenu Filter: 1
		option Butterworth
		option Hann
	real left_Formants_range_(Hz) 900
	real right_Formants_range_(Hz) 2000
	real Smoothing_frequency_(Hz) 10
	optionmenu Technique: 1
		option Derivative
		option Amplitude
	positive Threshold 0.08
	optionmenu Boundaries: 3
		option Onsets
		option Offsets
		option Both
	real Minimum_duration_(s) 0.020
	boolean Save_results 0
endform

### -------------------
### Check Praat version
### -------------------

if praatVersion < 6138
	exitScript: "The script needs at least version 6.1.38 of Praat.", newline$, "Your version is ", praatVersion$, ". Upgrade and run the script again."
endif

### ------------------------
### Shorten variable names
### ------------------------

# Cutoff frequencies
f_min = left_Formants_range
f_max = right_Formants_range

# Alert user if max frequency is smaller than min
if f_max < f_min
	exitScript: "Maximum frequency should be greater than ", f_min, "Hz. You entered ", f_max, " Hz."
endif

# Smoothing frequency to be applied to rectified signal
f_smooth = smoothing_frequency

# Minimum duration allowed between two consecutive boundaries.
mindur = minimum_duration

# Save results
save = save_results

### ----
### Mode
### ----

if mode = 1
	## Single file
	## -----------

	audioFile$ = chooseReadFile$: "Open a sound file"
	if audioFile$ <> ""
		audio = Read from file: audioFile$
		audio$ = selected$("Sound")
	else
		exitScript: "You have to select a WAV file."
	endif

	@detect: audio, filter, f_min, f_max, f_smooth, technique, threshold, boundaries, mindur

	if save = 1
		folder$ = left$(audioFile$, rindex(audioFile$, "\"))
		selectObject: detect.grid
		Save as text file: folder$ + audio$ + ".TextGrid"
		selectObject: detect.beat
		nowarn Save as WAV file: folder$ + audio$ + "_beat.wav"
		if technique = 1
			selectObject: detect.deriv
			nowarn Save as WAV file: folder$ + audio$ + "_deriv.wav"
		endif
	endif

	# Join audio and beatwave into a stereo file
	selectObject: audio, detect.beat
	stereo = Combine to stereo
	Rename: audio$ + "_wav-beat"

	# Clean objects list
	removeObject: audio, detect.beat
	if technique = 1
		removeObject: detect.deriv, detect.deriv2
	elsif technique = 2
		removeObject: detect.amp
	endif

	selectObject: stereo, detect.grid
	Edit
elsif mode = 2
	## Multiple files
	## --------------

	# Ensure sound file folder ends with a separator character
	if not(endsWith(sound_files$, "/") or endsWith(sound_files$, "\"))
		sound_files$ = sound_files$ + "/"
	endif

	soundFiles$# = fileNames$#(sound_files$ + "*" + sound_extension$)
	nfiles = size(soundFiles$#)
	for file to nfiles
		audio = Read from file: sound_files$ + soundFiles$#[file]
		audio$ = selected$("Sound")
		@detect: audio, filter, f_min, f_max, f_smooth, technique, threshold, boundaries, mindur

		# TextGrids are always saved in "Multiple files" mode
		selectObject: detect.grid
		Save as text file: sound_files$ + audio$ + ".TextGrid"

		# Beatwave is also saved when 'save' is TRUE
		if save = 1
			selectObject: detect.beat
			nowarn Save as WAV file: sound_files$ + audio$ + "_beat.wav"
			if technique = 1
				# Beatwave derivative is also saved
				selectObject: detect.deriv
				nowarn Save as WAV file: sound_files$ + audio$ + "_deriv.wav"
			endif
		endif

		# Clean objects list
		removeObject: audio, detect.beat, detect.grid
		if technique = 1
			removeObject: detect.deriv, detect.deriv2
		elsif technique = 2
			removeObject: detect.amp
		endif
	endfor
endif

procedure detect: .audio, .filter, .f_min, .f_max, .f_smooth, .technique, .threshold, .boundaries, .mindur
# Main steps
# ----------
# 1. Audio file filtering
# 2. Signal rectification
# 3. Beatwave generation and smoothing
# 4. Onsets and or offsets finding
#
# Input variables
# ---------------
# audio [num]: numerical ID of Sound object
# filter [num]: filter type (1: Butterworth, 2: Hann)
# f_min [num]: pass band lower edge
# f_max [num]: pass band upper edge
# f_smooth [num]: beatwave smoothing value 
# technique [num]: choice of technique for boundary finding (1: beatwave derivative, 2: amplitude)
# threshold [num]: cutoff value for the boundary finding procedure
# boundaries [num]: what boundaries to detect (1: onsets, 2: offsets, 3: both)
# mindur [num]: minimum time between consecutive boundaries

	### ---------
	### Filtering
	### ---------

	# Width of region between pass and stop regions
	# Same for both filters
	# Should not be too small
	.w = (.f_max - .f_min) / 2

	selectObject: .audio
	.audio$ = selected$("Sound")
	if .filter = 1
		# Band pass Butterworth filter
		# 2nd order is a good choice for this step (wider skirt)
		.order = 2
		.centerf = (.f_max + .f_min) / 2
		.filt = Filter (formula): "sqrt(1.0/(1.0 + ((x - .centerf) / .w)^(2 * .order))) * self"
	elsif filter = 2
		# Hann filter
		.filt = Filter (pass Hann band): .f_min, .f_max, .w
	endif
	Rename: .audio$ + "_filt"

	### -------------
	### Rectification
	### -------------

	selectObject: .filt
	.rect = Copy: .audio$ + "_rect"
	Formula: "abs(self)"

	### -------------------
	### Beatwave generation
	### -------------------

	selectObject: .rect
	if .filter = 1
		# Low pass Butterworth filter
		# 3rd order works best here
		# Tried 2nd order, but beatwave derivative gets too jagged
		.order = 3
		.beat = Filter (formula): "(1 / sqrt(1 + (x / .f_smooth)^(2 * .order))) * self"

	elsif filter = 2
		# Hann filter
		# Change smooth parameter 'w' as needed
		.w2 = 5
		.beat = Filter (pass Hann band): 0, .f_smooth, .w2
	endif

	Rename: .audio$ + "_beat"

	# Beatwave normalization
	@normalize: .beat

	### ----------------
	### Boundary finding
	### ----------------

	if technique = 1

		# Beatwave derivative
		# -------------------

		.deriv = Copy: .audio$ + "_deriv"
		Formula: "if col < ncol then (self[col+1] - self[col])/dx else 0 fi"
	
		if .boundaries = 1
			Formula: "if self > 0 then self else 0 fi"
		elsif .boundaries = 2
			Formula: "if self < 0 then abs(self) else 0 fi"
		elsif .boundaries = 3
			Formula: "abs(self)"
		endif

		# Normalize derivative of beatwave
		@normalize: .deriv

		# Filter out derivative maxima lower than threshold
		.deriv2 = Copy: .audio$ + "_deriv_amp"
		Formula: "if self >= .threshold then self else -1 fi"

		# Find maxima points in filtered beatwave derivative
		.bound = To PointProcess (extrema): 1, "yes", "no", "None"
	elsif technique = 2
		
		# Amplitude technique
		# -------------------

		selectObject: .beat
		.amp = Copy: .audio$ + "_amp"
		# Apply threshold to beatwave
		Formula: "if self >= .threshold then self else -1 fi"
		if .boundaries = 1
			.bound = To PointProcess (zeroes): 1, "yes", "no"
		elsif boundaries = 2
			.bound = To PointProcess (zeroes): 1, "no", "yes"
		elsif boundaries = 3 
			.bound = To PointProcess (zeroes): 1, "yes", "yes"
		endif
	endif

	### ============================
	### Create and populate TextGrid
	### ============================

	selectObject: .bound
	.nbound = Get number of points
	.previous = Get time from index: 1
	.previous = .previous - .mindur
	selectObject: .audio
	.grid = To TextGrid: "boundaries", ""

	for .i to .nbound
		selectObject: .bound
		.current = Get time from index: .i
		if (.current - .previous) >= .mindur
			selectObject: .grid
			Insert boundary: 1, .current
		endif
		.previous = .current
	endfor

	removeObject: .filt, .rect, .bound
endproc

procedure normalize: .obj
# Normalize Sound object to the [0, 1] interval
	selectObject: .obj
	.max = Get maximum: 0, 0, "None"
	.min = Get minimum: 0, 0, "None"
	Formula: "(self - .min) / (.max - .min)"
endproc
