# vowel-detector
# --------------
# 
# Finds onsets and offsets of segments in sound files based
# on their energy profile. It works better for vowel-like sounds.
# This is a complete rewrite of the BeatExtractor script coded by 
# P. A. Barbosa, in turn based on Fred Cummins' algorithm.
#
# Cummins, F., and Port, R. (1998). Rhythmic constraints on stress
#   timing in English. _Journal of Phonetics_, 26, 145–171.
#
# Pablo Arantes <pabloarantes@protonmail.com>
#
# created: 2014-04-11
#
# Copyright (C) 2014-2020  Pablo Arantes
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
	optionmenu Mode: 1
		option Single file
		option Multiple file
	optionmenu Filter: 1
		option Butterworth
		option Hann
	real left_Formants_range_(Hz) 900
	real right_Formants_range_(Hz) 2000
	real Smoothing_frequency_(Hz) 10
	positive Threshold 0.08
	optionmenu Boundaries: 3
		option Onsets
		option Offsets
		option Both
	real Minimum_duration_(s) 0.020
	boolean Save_results 0
endform

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
	audioFile$ = chooseReadFile$: "Open a sound file"
	if audioFile$ <> ""
		audio = Read from file: audioFile$
	else
		exitScript: "You have to select a WAV file."
	endif

	@segmentation: audio, filter, f_min, f_max, threshold, boundaries, mindur

	if save = 1
		folder$ = left$(audioFile$, rindex(audioFile$, "\"))
		selectObject: grid
		Save as text file: folder$ + audio$ + ".TextGrid"
		selectObject: beat
		nowarn Save as WAV file: folder$ + audio$ + "_beat.wav"
		if technique = 2
			selectObject: deriv
			nowarn Save as WAV file: folder$ + audio$ + "_deriv.wav"
		endif
	endif

	# Join audio and beatwave into a stereo file
	selectObject: audio, beat
	stereo = Combine to stereo
	Rename: audio$ + "_wav-beat"

	# Clean objects list
	removeObject: audio, beat, filt, rect, bound, deriv, deriv2

	selectObject: stereo, grid
	Edit
else
	## Multiple files
	folderName$ = chooseDirectory$: "Choose a directory to save all the files"
	if folderName$ <> ""
		files = Create Strings as file list: "fileList", folderName$ + "\*.wav"
		nfiles = Get number of strings
		for file to nfiles
			selectObject: files
			audioFile$ = Get string: file
			audio = Read from file: audioFile$
			@segmentation: audio, filter, f_min, f_max, threshold, boundaries, mindur

			# TextGrids are always saved in "Multiple files" mode
			selectObject: grid
			Save as text file: folderName$ + "\" + audio$ + ".TextGrid"

			# Beatwave and beatwave derivative are also saved when 'save' is TRUE
			if save = 1
				selectObject: beat
				nowarn Save as WAV file: folderName$ + "\" + audio$ + "_beat.wav"
				if technique = 2
					selectObject: deriv
					nowarn Save as WAV file: folderName$ + "\" + audio$ + "_deriv.wav"
				endif
			endif

			# Clean objects list
			removeObject: audio, beat, filt, rect, bound, grid, eriv, deriv2
		endfor
	endif
	removeObject: files
endif

procedure segmentation: audio, filter, f_min, f_max, threshold, boundaries, mindur

	### ---------
	### Filtering
	### ---------

	# Width of region between pass and stop regions
	# Same for both filters
	# Should not be too small
	w = (f_max - f_min) / 2

	selectObject: audio
	audio$ = selected$("Sound")
	if filter = 1
		# Band pass Butterworth filter
		# 2nd order is a good choice for this step (wider skirt)
		order = 2
		centerf = (f_max + f_min) / 2
		filt = Filter (formula): "sqrt(1.0/(1.0 + ((x - centerf) / w)^(2 * order))) * self"
	elsif filter = 2
		# Hann filter
		filt = Filter (pass Hann band): f_min, f_max, w
	endif
	Rename: audio$ + "_filt"

	### -------------
	### Rectification
	### -------------

	selectObject: filt
	rect = Copy: audio$ + "_rect"
	Formula: "abs(self)"

	### -------------------
	### Beatwave generation
	### -------------------

	selectObject: rect
	if filter = 1
		# Low pass Butterworth filter
		# 3rd order works best here
		# Tried 2nd order, but beatwave derivative gets too jagged
		order = 3
		beat = Filter (formula): "(1 / sqrt(1 + (x / f_smooth)^(2 * order))) * self"

	elsif filter = 2
		# Hann filter
		# Change smooth parameter 'w' as needed
		w2 = 5
		beat = Filter (pass Hann band): 0, f_smooth, w2
	endif

	Rename: audio$ + "_beat"

	# Beatwave normalization
	@normalize: beat

	### ----------------
	### Boundary finding
	### ----------------

	# Beatwave derivative
	deriv = Copy: audio$ + "_deriv"
	Formula: "if col < ncol then (self[col+1] - self[col])/dx else 0 fi"
	if boundaries = 1
		Formula: "if self > 0 then self else 0 fi"
	elsif boundaries = 2
		Formula: "if self < 0 then abs(self) else 0 fi"
	else
		Formula: "abs(self)"
	endif
	# Normalize derivative of beatwave
	@normalize: deriv

	# Filter out derivative maxima lower than threshold
	deriv2 = Copy: audio$ + "_deriv_amp"
	Formula: "if self >= threshold then self else -1 fi"

	# Find maxima points in filtered beatwave derivative
	bound = To PointProcess (extrema): 1, "yes", "no", "None"

	### ============================
	### Create and populate TextGrid
	### ============================

	selectObject: bound
	nbound = Get number of points
	previous = Get time from index: 1
	previous = previous - mindur
	selectObject: audio
	grid = To TextGrid: "boundaries", ""

	for i to nbound
		selectObject: bound
		current = Get time from index: i
		if (current - previous) >= mindur
			selectObject: grid
			Insert boundary: 1, current
		endif
		previous = current
	endfor

endproc

procedure normalize: .obj
# Normalize Sound object to the [0, 1] interval
	selectObject: .obj
	max = Get maximum: 0, 0, "None"
	min = Get minimum: 0, 0, "None"
	Formula: "(self - min) / (max - min)"
endproc
