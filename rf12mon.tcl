#!/usr/bin/tclsh8.6

## ------------------------------------------------------
## A simple spectrum analyzer for the RF12B radio module
## (C)2013, D.Zachariadis
## ------------------------------------------------------


proc ::init {} {
	if {[catch {
		package req Tk
	}]} {
		exit
	}
	wm withdraw .
}
#
init

namespace eval ::rf {

# namespace ::rf
proc avgList list {
expr double([join $list +])/[llength $list]
}

# namespace ::rf
proc bildBinds {} {
	variable var
	set W $var(scr)

	bind $W <Motion> [list [namespace current]::onEvent Motion %x %y %s]
	bind $W <1> [list [namespace current]::onEvent B1 %x %y %X %Y %s]
	bind $W <3> [list	[namespace current]::onEvent B3 %x %y %X %Y %s]
	bind $W <Button-4> {
		event generate %W <<MouseWheel>> -data 120 -x %x -y %y -state %s
		break
	}
	bind $W <Button-5> {
		event generate %W <<MouseWheel>> -data -120 -x %x -y %y -state %s
		break
	}
	bind $W <<MouseWheel>> "
		[namespace current]::onEvent Wheel %x %y %s %d
		break
	"
	bind $W <<PortChanged>> [namespace current]::onPortChange
	$W bind M <Button-4> {
		event generate %W <<MouseWheel>> -data 120 -x %x -y %y -state %s
		break
	}
	$W bind M <Button-5> {
		event generate %W <<MouseWheel>> -data -120 -x %x -y %y -state %s
		break
	}
	$W bind M <<MouseWheel>> "
		[namespace current]::onEvent MarkWheel %x %y %s %d
		break
	"
	bind $var(evente) <Key> "
		if {\"%K\" eq \"Return\" || \"%K\" eq \"KP_Enter\"} {
			[namespace current]::setEventText
		}
	"
}

# namespace ::rf
proc buildEventPopup {{W .mon}} {
	variable var
	catch {
		destroy $W.evepopu
	}
	set var(evepopu) [menu $W.evepopu -bg #f0f0f0 -bd 1 -tearoff 0  -activeborderwidth 0 -font {TkDefaultFont -11}  -postcommand {} -relief raised -tearoff 0 -title "Commands"]
	$var(evepopu) add command -label "Edit mark" -command [list [namespace current]::editMark Edit]
	$var(evepopu) add command -label "Clear mark" -command [list [namespace current]::editMark Delete]
}

# namespace ::rf
proc buildGui {{W .mon}} {
	variable var

	destroy $W
	catch {
		image delete [namespace current]::wf
	}
	if {$W eq "."} {
		set W ""
	} else {
		destroy $W
		toplevel $W
	}
	wm title $W "RF12B spectrum monitor"
	wm geometry $W 796x485
	wm protocol $W WM_DELETE_WINDOW [namespace current]::quit
	wm resizable $W 0 0
	::ttk::style configure bold.TButton -font {TkDefaultFont -14 bold} -foreground #444
	::ttk::style theme use clam

	# screen canvas
	set var(scr) $W.scr
	pack [canvas $var(scr) -background black -width $var(W) -height $var(H) -xscrollincrement 1] -side left -anchor nw
	# move canvas origin to the right
	$var(scr) xview scroll -$var(leftmargin) u

	# create event editing widget
	catch {image delete [namespace current]::clr}
	image create photo [namespace current]::clr -data {
R0lGODlhDQAMAIQQAAABABIUESYoJU9RTlhaV2RlY3Z4dY2PjJWXlJ2fnKWn
pNTX0+Di3+bo5efp5vz++///////////////////////////////////////
/////////////////////////yH5BAEKAAwALAAAAAANAAwAAAVCIPOITFmO
Y7kUCaoUi/kMANAm9ZA+Rg0cPkNKRPDVCMMTLZdU+nSmU9GIlBV8wFohtfAp
HgpfTCT4oYCC4aOhdqRCADs=
}
	::ttk::frame $var(scr).edf
	set var(evente) [::ttk::entry $var(scr).edf.ede -width 15 -font {TkDefaultFOnt -9} -textvariable [namespace current]::var(edetxt)]
	pack $var(evente) -side left -anchor w
	pack [::ttk::button $var(scr).edf.clr -image [namespace current]::clr -padding 0 -command "
		[namespace current]::editMark delete
	"] -side left -anchor w
	set var(eventi) [$var(scr) create window 0 480 -window $var(scr).edf -tags EE -state hidden -anchor w]

	# waterfall blank image
	set var(wfi) [image create photo [namespace current]::wf]
	$var(wfi) config -width $var(scan,W) -height $var(wf,H)
	# black backround
	$var(wfi) put #000 -to 0 0 $var(scan,W) $var(wf,H)
	# put waterfall image on the screen canvas
	puts [$var(scr) create image 0 $var(wf,top) -image $var(wfi) -anchor nw -tags {wfi fx}]
	# create controls
	pack [::ttk::frame $W.tbf -padding 5] -fill y -side left
	set w $W.tbf.portlf
	pack [::ttk::labelframe $w -text "Port:" -padding {2 2}] -anchor nw -pady 5
	pack [::ttk::combobox $w.portcb -textvariable [namespace current]::var(portname) -values [enumeratePorts] -width 12 -postcommand "
		$w.portcb config -values \[[namespace current]::enumeratePorts]
	"] -anchor nw
	bind $w.portcb <<ComboboxSelected>> "
		[namespace current]::portSetup
		set [namespace current]::var(scanbtn) Stop
	"

	pack [::ttk::button $W.tbf.scanb -style bold.TButton -text "Scan" -command [namespace current]::toggleScan -textvariable [namespace current]::var(scanbtn) -width 15 -padding {0 7}] -anchor w -pady 4
	pack [::ttk::button $W.tbf.clrb -text "Clear screen" -command [list [namespace current]::clear screen] -width 15 -padding {0 7}] -anchor w -pady 4

	set w [::ttk::labelframe $W.tbf.alcf -text "Auto contrast" -padding {5 2} -width 15]
	pack $w -anchor nw
	pack [::ttk::checkbutton $w.alcb -text "On" -onvalue on -offvalue off -variable [namespace current]::var(alc,on) -command "
		if {\$[namespace current]::var(evealc,on)} {
			[namespace current]::drawMark \"Auto contrast \$[namespace current]::var(alc,on)\" -tag 1
			set [namespace current]::var(maxrssi) 1
		}
	" -padding {0 0}] -anchor w -side top
	pack [::ttk::label $w.alcsl -text "Avg lines:"] -anchor w -side left
	pack [::ttk::spinbox $w.alcsb -width 2 -from 1 -to 99 -increment 1 -textvariable [namespace current]::var(alc,avgln) -validate all -validatecommand {
		if {![string is integer -strict %S%s] || %S%s <= 0} {return 0} else {return 1}
	}] -anchor w -side left

	set w [::ttk::labelframe $W.tbf.specf -text "Spectrum" -padding {5 2} -width 15]
	pack $w -anchor nw -pady 5
	pack [::ttk::checkbutton $w.maxcb -text "Show max" -width 12 -variable [namespace current]::var(maxs,on) -command "
		if {\$[namespace current]::var(maxs,on)} {
			\$[namespace current]::var(scr) itemconfig maxs -state normal
		} else {
			\$[namespace current]::var(scr) itemconfig maxs -state hidden
		}
	"] -anchor nw -side top
	pack [::ttk::checkbutton $w.avgscb -text "Show avg" -width 12 -variable [namespace current]::var(avgs,on) -command "
		if {\$[namespace current]::var(avgs,on)} {
			\$[namespace current]::var(scr) itemconfig asal -state {}
		} else {
			\$[namespace current]::var(scr) itemconfig asal -state hidden
		}
	"] -anchor nw -side top
	pack [::ttk::label $w.avgl -text "Avg lines:"] -anchor w -side left
	pack [::ttk::spinbox $w.avgsb -width 2 -from 1 -to 99 -increment 1 -textvariable [namespace current]::var(spec,avgln)] -anchor w -side left

	set w $W.tbf.evlf
	pack [::ttk::labelframe $w -text "Auto marks:" -padding {2 2}] -anchor nw -pady 5
	pack [::ttk::checkbutton $w.pchcb -text "Port change" -width 12 -variable [namespace current]::var(evepch,on)]
	pack [::ttk::checkbutton $w.alccb -text "Auto contrast\nchange" -width 12 -variable [namespace current]::var(evealc,on)]

#	pack [::ttk::button $W.tbf.prefsb -text "Preferences ..." -command [namespace current]::buildPrefs -width 15 -padding {0 7}] -anchor w -pady 4
	update
	buildPopup
	buildScreen
	bildBinds
}

# namespace ::rf
proc buildPopup {{W .mon}} {
	variable var
	#popup window
	catch {
		destroy $W.popup
	}
	set var(popup) [menu $W.popup -bg #f0f0f0 -bd 1 -tearoff 0  -activeborderwidth 0 -font {TkDefaultFont -11}  -postcommand {} -relief raised -tearoff 0 -title "Commands"]

	$var(popup) add command -label "Mark event" -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark Event \$x \$y
	"
	$var(popup) add command -label "Mark time" -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark TMark \$x \$y
	"
	$var(popup) add command -label "Mark freq." -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark FMark \$x \$y
	"
	$var(popup) add command -label "Mark port" -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark Port \$x \$y
	"
	$var(popup) add separator
	$var(popup) add command -label "Clear mark" -command [list [namespace current]::editMark Delete]
	$var(popup) add command -label "Clear marks" -command [list [namespace current]::clear marks]
	$var(popup) add command -label "Clear spectrum" -command [list [namespace current]::clear spectrum]
	$var(popup) add command -label "Restart" -command [list [namespace current]::clear screen]
}

# namespace ::rf
proc buildPrefs {{W .prefs}} {
	variable var

	destroy $W
	toplevel $W
	#wm geometry $W 480x320
	wm title $W "rf12mon preferences"

	set w $W.nb
	pack [::ttk::notebook $w] -fill both -expand 1
	# build tabs
	foreach f {ports controls colors} {
		set fw [::ttk::frame $w.[string range $f 0 2]f]
		$w add $fw -text [string totitle  $f]
	}
	# build lines
	set w $w.porf
	pack [::ttk::frame $w.tf]
	foreach {p ww} {name 15 desc 20 use 0} {
		pack [::ttk::label $w.tf.[string range $p 0 1]l -text $p -width $ww] -side left
	}
	set i 1
	foreach p [enumeratePorts] {
		pack [::ttk::frame $w.line$i] -fill x
		pack [::ttk::label $w.line$i.pl -text $p -width 15] -side left
		pack [::ttk::entry $w.line$i.pe -width 20 -textvariable [namespace current]::var(port,desc,$p)] -side left
		pack [::ttk::checkbutton $w.line$i.pu -textvariable [namespace current]::var(port,use,$p) -padding 2] -side left -anchor c
		incr i
	}
}

# namespace ::rf
proc buildScreen {} {
	variable var

	set ttcolor #ccc
#	lassign [split [winfo geometry $var(scr)] x+] var(W) var(H) var(X) var(Y)
	$var(scr) del [list ! (wfi || EE)]
	# screen borders
	$var(scr) create line 0 0 0 $var(sabase) -tags [list st stv fx] -fill #444
	$var(scr) create line -500 $var(wf,top) $var(W) $var(wf,top) -tags [list st sth fx] -fill #444
	$var(scr) create line $var(scan,W) 0 $var(scan,W) $var(sabase) -tags [list st stv fx] -fill #444
	$var(scr) create line -500 [expr {$var(wf,H) + $var(wf,top)}] $var(W) [expr {$var(wf,H) + $var(wf,top)}] -tags [list st sth fx] -fill #444
	$var(scr) create text -50 5 -text "Time" -anchor nw -font {TkDefaultFont -10 bold} -fill $ttcolor -tags {tmt fx tt}
	$var(scr) create text -58 23 -text "" -anchor w -font {TkDefaultFont -9} -fill #666 -tags {clock}
	$var(scr) create text -50 [expr {$var(wf,H) + $var(wf,top) + 5}] -text "dBm" -anchor nw -font {TkDefaultFont -10 bold} -fill $ttcolor -tags {gat fx tt}
	$var(scr) create text 5 [expr {$var(wf,top) - 15}] -text "MHz" -anchor w -fill #666 -tags {hzt fx} -font {TkDefaultFont -12 bold}
	$var(scr) create text [expr {$var(W) - $var(leftmargin) - 10}] 5 -text "Events" -anchor ne -fill $ttcolor -tags {evt fx tt} -font {TkDefaultFont -11 bold}
	$var(scr) create text [expr {$var(W) - $var(leftmargin) - 10}] [expr {$var(wf,H) + $var(wf,top) + 5}] -text "Spectrum" -anchor ne -fill $ttcolor -tags {sat fx tt} -font {TkDefaultFont -11 bold}
	# draw grid
	for {set f 861} {$f < 880} {incr f 2} {
		set x [freq2scr $f]
		$var(scr) create line $x $var(wf,top) $x [expr {$var(H) - 20}] -fill #222 -tags [list g gx gxl g$x fx] -dash {2 2}
		$var(scr) create text $x [expr {$var(sabase) + 5}] -anchor n -text $f -tags [list g gt gxt g$x fx] -fill #666 -font {TkDefaultFont -10}
	}
	for {set dBm 0} {$dBm < $var(RSr)} {incr dBm $var(RSstep)} {
		set y [expr {$var(sabase) - $var(spec,dBppx) * $dBm}]
		$var(scr) create line 0 $y $var(scan,W) $y -fill #222 -tags [list g gy gyl g$y fx] -dash {2 2}
		$var(scr) create text -5 $y -anchor e -text [expr {$var(Pmin) + $dBm}] -tags [list g gt gyt g$x fx] -fill #666 -font {TkDefaultFont -10}
	}
	# create current scan line
	$var(scr) create line 0 $var(wf,top) $var(scan,W) $var(wf,top) -tags cscl -fill #800
	# vertical x cursor
	set ty [expr {$var(wf,top) - 11 - 9 * ($var(markcnt) %2)}]
	set x 0
	set tx [expr {$x + 6}]
	$var(scr) create line $tx $ty $x $ty $x $var(wf,top) -arrow last -arrowshape {6 7 3} -fill #ffffff -tags [list xc xca fx c]
	$var(scr) create text $tx $ty -text [format " %0.2f GHz" [expr {($var(f1) + $x * $var(scale))/1000.0}]] -fill #fff -font {TkDefaultFont -9} -anchor w -tags [list xc xct fx c]
	$var(scr) create line $x $var(wf,top) $x $var(H) -fill #444 -tags [list xc xcl fx c]
	# horizontal raw cursor 
	$var(scr) create line 0 0 0 0 -fill #444 -dash {2 2} -tags [list yc yccl fx c] 
	$var(scr) create text -5  $var(H) -text "" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list yc yct fx c]
	# horizontal avg cursor 
	$var(scr) create line 0 0 0 0 -fill #444 -dash {2 2} -tags [list yc ycl ycal fx c]
	$var(scr) create text -5  $var(H) -text "" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list yc yct ycat fx c]
	# time cursor
	$var(scr) create line 0 0 0 0 -fill #fff -tags [list tc tca fx c] -arrow last -arrowshape {6 7 3}
	$var(scr) create line 0 0 0 0 -tags {tc tcl fx c} -dash {2 2} -fill #444
	$var(scr) create text -5  0 -text "" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list tc tct fx c]
	$var(scr) itemconfig [list xcl || ycl] -dash {2 2}
	# spectrum lines
	$var(scr) create poly 0 0 0 0 -fill #88f -tags {sa csa csal}
	$var(scr) create line 0 0 0 0 -fill #c63 -tags {sa asa asal}
	$var(scr) create text [expr {$var(rightmargin) + 60}] [expr {$var(sabase) + 10}] -anchor nw -fill #88f -font {TkDefaultFont -10} -text "Raw" -tags {sa csa csat} 
	$var(scr) create text [expr {$var(rightmargin) + 90}] [expr {$var(sabase) + 10}] -anchor nw -fill #f84 -font {TkDefaultFont -10} -text "Avg" -tags {sa asa asat}
	$var(scr) create text $var(rightmargin) [expr {$var(wf,H) + $var(wf,top) + 5}] -anchor nw -fill #666 -font {TkDefaultFont -10 bold} -text " max" -tags {maxrssit}
	$var(scr) create text $var(rightmargin) $var(sabase) -anchor w -fill #fff -font {TkDefaultFont -10} -text "$var(Pmin) dBm" -tags {maxrssi}
	# spectrum x axis
	$var(scr) create line 0 $var(sabase) $var(scan,W) $var(sabase) -tags [list sax fx] -fill #222
}

# namespace ::rf
proc clear what {
	variable var

	switch -glob -- $what {
		"scr*" {
			$var(scr) delete [list !(fx || EE)]
			# blank waterfall image
			$var(wfi) put #000 -to 0 0 480 300
			initFreqArray
			buildScreen
		}
		"spec*" {
			$var(wfi) put #000 -to 0 0 480 300
			initFreqArray
		}
		"marks" {
			$var(scr) delete M E
		}
	}
}

# namespace ::rf
proc cloneItem {W item tags} {
	foreach it $item {
	foreach i [$W find withtag $it] {
		set new [$W create [$W type $i] [$W coords $i]]
		set opts {}
		foreach o [$W itemconfig $i] {
			lassign $o opt _ _ _ val
			lappend opts $opt $val
		}
		lappend opts -tags $tags
		$W itemconfig $new {*}$opts
	}
	}
	return $new
}

# namespace ::rf
proc cursor2event {tag tags} {
	variable var
	# arrow
	$var(scr) create line [$var(scr) coords ${tag}a] {*}[dict merge [opts2dict $var(scr) ${tag}a] [list -tags [concat $tags Mal] -fill #fff]]
	# frequency
	set coords [$var(scr) coords ${tag}t]
	$var(scr) create text $coords {*}[dict merge [opts2dict $var(scr) ${tag}t] [list -tags [concat $tags Mt] -fill #fff]]
	if {$tag eq "tc"} {
		$var(scr) create text $var(rightmargin) [lindex $coords 1] {*}[dict merge [opts2dict $var(scr) ${tag}t] [list -tags [concat $tags Met] -fill #fff -text "Mark $var(markcnt)" -anchor w]]
	}
	# frequency line
	$var(scr) create line [$var(scr) coords ${tag}l] {*}[dict merge [opts2dict $var(scr) ${tag}l] [list -tags [concat $tags Ml] -fill #666]]
}

# namespace ::rf
proc deleteMark r {
	variable var

	unset -nocomplain var(M,mark)
	$var(scr) del r$var(r)
}

# namespace ::rf
proc drawEvent args {
	variable var
	# args are x, y, mark
	lassign $args x y mark
	if {$mark ne {}} {
		# set the center of the circle. It will also tell the event parsing proc that we are in the middle of drawing an event circle
		set var(B1) $args
		return
	}
	# the mouse is moving, draw the new circle
	lassign $var(B1) x0 y0 mark
	set dx [expr {abs($x - $x0)}]
	set dy [expr {abs($y - $y0)}]
	$var(scr) coords [list $mark && Mo] [expr {$x0 - $dx}] [expr {$y0 - $dy}] [expr {$x0 + $dx}] [expr {$y0 + $dy}]
}

# namespace ::rf
proc drawMark {txt args} {
	variable var

	if {![dict exists $args -r]} {
		set row  $var(r)
	} else {
		set r [dict get $args -r]
		set row [expr {$r - $var(wf,top)}]
	}
	if {[dict exists $args -tags]} {
		set tags [dict get $args -tags]
	} else {
		set tags {}
	}
	set r [expr {$var(wf,top) + $row}]
	incr var(markcnt)

	$var(scr) create line 0 $r $var(scan,W) $r -dash {2 2} -fill #666 -tags [list M Ml Mhl r$row M$var(markcnt)]
	set itxt [$var(scr) create text [expr {$var(rightmargin) + 10}] $r -text $txt -fill #fff -font {TkDefaultFont -11} -anchor w -tags [concat M Mt Met r$row M$var(markcnt) $tags]]

	if {[info exists var(clock,$row)]} {
		$var(scr) create text -3 $r -text "[clock format $var(clock,$row) -format %H:%M:%S]" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list M T Mt r$var(r) M$var(markcnt)]
	}
}

# namespace ::rf
proc drawScanline {} {
	variable var

	set r [expr {$var(wf,top) + $var(r)}]
	# delete events from previous scans on this row
	editMark delete $var(r)
	# move current scan line
	$var(scr) coords cscl 0 $r $var(scan,W) $r
	# don't draw line if it contains non numbers
	if {[catch {
		set maxrssi [::tcl::mathfunc::max {*}$var(scandata)]
	}]} {
		return
	}
	# calculate maxrs to use in case ALC is on
	if {!$var(alc,on) || $maxrssi > $var(RSlev)} { 
		set maxrs $var(RSlev)
	} else {
		set maxrs $maxrssi
	}
	# keep a list of alc,avgln maxrssis for calculating average ALC
	lappend var(maxrssis) $maxrs
	if {$var(alc,on)} {
		set var(maxrssis) [lrange $var(maxrssis) end-[expr {$var(alc,avgln)-1}] end]
		set maxrs [expr {max([avgList $var(maxrssis)],$maxrs)}]
	}
	# store the alc that was used to derive the pixels in the waterfall spectrum, this will help recover the signal values from the pixels later.
	set var(maxrssi,$var(r)) $maxrs
	# save a division from doing it in the loop
	set rrssi [expr {$var(RSlev) / double($maxrs)}]
	lassign {} scanline maxs
	set len [llength $var(scandata)]
	set len [expr {$len < $var(scan,W) ? $len : $var(scan,W)}]
	set coords [list 0 $var(sabase)]
	for {set i 0} {$i < $len} {incr i} {
		set ovrld {}
		set rssi [lindex $var(scandata) $i]
		#
		if {$rssi > $var(RSlev)} {
			set rssi $var(RSlev)
			lappend ovrld $i
		} elseif {$rssi == $maxrssi} {
			lappend maxs $i
		}
		if {$ovrld ne {}} {
			# draw pixel in overload color
			lappend scanline #f88
		} else {
			lappend scanline $var(wfcolor,[expr {int($rrssi * $rssi)}])
		}
		# current frequency point
		lappend coords $i [expr {$var(sabase) - 15 * $rssi}]
		# average freq points
		set var(fp,$i) [expr {($var(fp,$i)*($var(spec,avgln) - 1) + double($rssi)) / $var(spec,avgln)}]
	}
	# plot current spectrum line
	lappend coords $var(scan,W) $var(sabase)
	$var(scr) coords csal $coords
	# plot avg spectrum line
	if {$var(avgs,on)} {
		set coords [list 0 $var(sabase)]
		for {set i 0} {$i < $var(scan,W)} {incr i} {
			lappend coords $i [expr {$var(sabase) - 15 * $var(fp,$i)}]
		}
		$var(scr) coords asal $coords
	}
	# draw waterfall spectrum line
	$var(wfi) put [list $scanline] -to 0 $var(r)
	# draw maxrssi
	$var(scr) itemconfig maxrssi -text "[expr {round($var(Pmin) + $var(RSstep) * $maxrssi)}] dBm"
	set y [expr {$var(sabase) - 15 * $maxrssi}]
	$var(scr) coords maxrssi $var(rightmargin) $y
	$var(scr) del maxs ovrld
	foreach m $maxs {
		$var(scr) create rect [expr {$m - 3}] [expr {$y - 3}] [expr {$m + 3}] [expr {$y + 3}] -tags maxs -outline #8f4 -state [expr {$var(maxs,on)? "normal" :"hidden"}]
	}
	foreach m $ovrld {
		$var(scr) create rect [expr {$m - 2}] [expr {$y - 2}] [expr {$m + 2}] [expr {$y + 2}] -tags maxs -outline #f00 -fill #f00
	}
	updateCursors [expr {int([$var(scr) canvasx $var(sx)])}] [expr {int([$var(scr) canvasy $var(sy)])}]
}

# namespace ::rf
proc editMark {e {row {}}} {
	variable var

	switch -nocase -glob -- $e {
		"Edit" {
			lassign $var(popup,xy) x y tags
			# get mark number and row
			set tag [regexp -inline -- {M[0-9]+} $tags]
			regexp -- {r([0-9]+)} $tags _ r
			lassign [$var(scr) bbox [list $tag && Met]] w n e s
			# ... and use them to place the entry widget
			$var(scr) coords EE 480 [expr {$r + $var(wf,top)}]
			set var(edetxt) [$var(scr) itemcget [list $tag && Met] -text]
			$var(scr) itemconfig EE -state normal -tags [list EE R$r $tag]
			$var(evente) select range 0 end
			focus $var(evente)
		}
		"Del*" {
			if {$row ne {}} {
				# delete all marks on row 
#				unset -nocomplain var(M,mark)
				if {"R$row" in [$var(scr) itemcget EE -tags]} {
					# entry editing is visible, close it
					$var(scr) itemconfig EE -tags EE -state hidden
				}
				$var(scr) del r$row
			} else {
				lassign $var(popup,xy) x y tags
				set tag [regexp -inline -- {M[0-9]+} $tags]
				$var(scr) del [list $tag && M]
				$var(scr) itemconfig EE -tags EE -state hidden
			}
		}
	}
}

# namespace ::rf
proc enumeratePorts {} {
	glob -nocomplain /dev/ttyUSB* /dev/ttyACM*
}

# namespace ::rf
proc freq2scr f {
	variable var
	# f = 860 + 20 *($var(f1) + $x * 8) / 4000.0
	expr {(($f - 860) * 4000.0 - 20 * $var(f1)) / 8.0 / 20.0}
}

# namespace ::rf
proc init {} {
	variable var

	array set var {
		W 670
		H 485
		scan,W 476
		wf,H 300
		wf,top 30
		leftmargin 70
		B1 {}
		sx 0
		sy 0

		r 0
		initok 0
		markcnt 0
		maxrssi 1
		maxrssis {1}
		rssis {}
		portname ""
		port {}
		ports {}
		scale 8
		scandata {}
		scanbtn Scan
		sabase 460
		rightmargin 480

		wfcolor,0 #000
		wfcolor,1 #226
		wfcolor,2 #448
		wfcolor,3 #66a
		wfcolor,4 #88c
		wfcolor,5 #aae
		wfcolor,6 #ddf
		wfcolor,7 #fff
		wfcolor,8 #ff0
		alc,avgln 2
		spec,avgln 5
		alc,on off
		evealc,on 1
		evepch,on 1
		maxs,on off
		avgs,on 1

		dBm,0 -110
		dBm,1 -104
		dBm,2 -98
		dBm,3 -92
		dBm,4 -86
		dBm,5 -80
		dBm,6 -74
		dBm,7 -68
		dBm,8 -62

		f1 96
		f2 3903
		Pmin -110
		RSr 46
		RSstep 6
		RSresp 500
	}
	set var(clock,0) [clock sec]
	# calculate dBs per pixel
	set var(spec,dBppx) [expr {($var(sabase) - $var(wf,top) - $var(wf,H) - 15) / double($var(RSr))}]
	# number of RSSI levels
	set var(RSlev) [expr {int($var(RSr) / double($var(RSstep)))}]
	initFreqArray
	set var(clock) [clock sec]
	set var(ports) [enumeratePorts]
	buildGui
}

# namespace ::rf
proc initFreqArray {} {
	variable var
	# initialize frequency point array
	for {set i 0} {$i < 476} {incr i} {
		set var(fp,$i) 0
	}
	array unset var clock,*
	array unset var maxrssi,*
	array set var [list clock,0 [clock sec] r 0]
}

# namespace ::rf
proc inside? {cx cy} {
	variable var

	set tags [$var(scr) gettags current]
	if {"M" in $tags} {
		return $tags
	} else {

		foreach i [$var(scr) find withtag Mo] {
			lassign [$var(scr) bbox $i] w n e s
			# find if the item encloses the point clicked
			if {$cx >= $w && $cy >= $n && $cx <= $e && $cy <= $s} {
				# we are within the square bbox. That's not a circle though ...
				return [$var(scr) gettags $i]
			}
		}
	}
}

# namespace ::rf
proc mark {e args} {
	variable var

	# canvas x,y
	lassign $args x y
	set row [expr {$y - $var(wf,top)}]
	set W $var(scr)
	switch -glob -nocase -- $e {
		"FMark" {
			cursor2event xc [list M F M$var(markcnt) r$row]
			incr var(markcnt)
		}
		"TMark" {
			cursor2event tc [list M T Mt M$var(markcnt) r$row Et]
			incr var(markcnt)
		}
		"Event" {
			cursor2event xc [list M E M$var(markcnt) r$row]
			cursor2event tc [list M E M$var(markcnt) r$row Et]
			$var(scr) create oval [expr {$x - 5}] [expr {$y - 5}] [expr {$x + 5}] [expr {$y + 5}] -tags [list M E Mo M$var(markcnt) r$row] -outline #f60
			# let user change the diameter of the oval
			drawEvent $x $y M$var(markcnt)
		}
		"Port" {
			if {$var(portname) ne "" && $var(port) ne ""} {
				drawMark "[file tail $var(portname)]" -tag 1 -tags P
			} else {
				portSetup
			}
		}
	}
}

# namespace ::rf
proc onEvent {e args} {
	variable var

	lassign $args var(sx) var(sy) X Y s
	set x [expr {int([$var(scr) canvasx $var(sx)])}]
	set y [expr {int([$var(scr) canvasy $var(sy)])}]
	set W $var(scr)

	switch -nocase -glob -- $e {
		"Mot*" {
			if {$var(B1) ne {}} {
				drawEvent $x $y
				return
			}

			set ty [expr {$var(wf,top) - 11 - 9 * ($var(markcnt) %2)}]
			set tx [expr {$x + 6}]

			if {$y > $var(wf,top) && $x > 0} {
				if {$x < $var(scan,W)} {
					# cursor within the waterfall or spectrum plot
					$W itemconfig [list xct || xcl || xca || tct || tcl] -state normal
					$W coords xca $tx $ty $x $ty $x $var(wf,top)
					$W coords xct $tx $ty
					$W itemconfig xct -text [format " %0.2f" [scr2freq $x]]
					$W coords xcl $x $var(wf,top) $x $var(sabase)
					# update spectrum analyser cursors
					updateCursors $x $y
					if {$y < ($var(wf,top) + $var(wf,H))} {
						# cursor in waterfall
						$W configure -cursor none
					} else {
						$W configure -cursor {}
					}
				} else {
					$W configure -cursor {}
					# hide frequency cursor
					$W itemconfig [list xct || xcl || xca] -state hidden
				}
				set row [expr {$var(sy) - $var(wf,top)}]
				if {$row > 0 && $row < $var(wf,H) && $x < ($var(rightmargin) + 80) } {
					# show time cursor
					$W itemconfig tc -state normal
					$W coords tct -15 $y
					$W coords tca -12 $y 0 $y
					$W coords tcl 0 $y $var(scan,W) $y
					if {[info exists var(clock,$row)]} {
						$W itemconfig tct -text "[clock format $var(clock,$row) -format %H:%M:%S]"
					} else {
						$W itemconfig tct -text "No data"
					}
					$W itemconfig tc -state normal
				} else {
					# hide time cursor
					$W itemconfig tc -state hidden
				}
			} else {
				# cursor outside the frequency band to the left
				$W configure -cursor {}
				$W itemconfig [list xct || xcl || xca || tc] -state hidden
			}
			$W raise yc
		}
		"B1" {
			if {$var(B1) ne {}} {
				set var(B1) {}
				incr var(markcnt)
			} elseif {[$W itemcget EE -state] eq "normal"} {
				setEventText
				$W itemconfig EE -state hidden -tags EE
			} elseif {[set tags [inside? $x $y]] ne {} && "F" ni $tags} {
				set var(popup,xy) [list $x $y $tags]
				editMark Edit
			}
		}
		"B3" {
			set var(B1) {}
			$W itemconfig EE -state hidden -tags EE
			set tags [inside? $x $y]
			set var(popup,xy) [list $x $y $tags]
			tk_popup $var(popup) $X $Y
		}
		"wheel" {
			puts $args
		}
		default {
			puts default\t$e\t$args
		}
	}
}

# namespace ::rf
proc onPortChange {} {
	variable var

	if {$var(portname) eq "" || ! $var(evepch,on)} return
	drawMark "[file tail $var(portname)]" -tag 1 -tags {M P Mt M$var(markcnt) Et}
}

# namespace ::rf
proc opts2dict {W tag} {
	set opts {}
	foreach o [$W itemconfig $tag] {
		lassign $o opt _ _ _ val
		lappend opts $opt $val
	}
	return $opts
}

# namespace ::rf
proc parseScandata {} {
	variable var

	if {! $var(initok) && [string match "*um]" $var(scandata)]} {
		set var(initok) 1
		return
	}
	# data is in array element var(scandata)
	drawScanline
}

# namespace ::rf
proc portError err {

	if {[regexp -- {couldn't open "(.*)"} $err _ port] && [string trim $port] eq ""} {
		set msg "No port defined"
	} else {
		set msg "Wrong port"
	}
	tk_messageBox -message $msg -detail "Please select a port\nconnected to the receiver" -icon info
}

# namespace ::rf
proc portSetup {} {
	variable var

	catch {
		close $var(port)
	}
	set var(initok) 0
	if {[catch {
		set var(port) [open $var(portname) RDWR]
	} err]} {
		portError $err
		set var(scanbtn) "Scan"
		# skip toggleScan resume
		return -level 2
	}
	# empty input buffer
	chan config $var(port) -blocking 0 -buffering line -mode 57600,n,8,1
	read $var(port)
	chan event $var(port) read [list [namespace current]::receive $var(port)]
	event generate $var(scr) <<PortChanged>>
}

# namespace ::rf
proc quit {} {
	variable var
	catch {
		chan close $var(port)
	}
	exit
}

# namespace ::rf
proc receive port {
	variable var

	if {![gets $port data] || ![string length $data]} {
		return
	}
	if {$var(r) < $var(wf,H)} {
		incr var(r)
	} else {
		set var(r) 0
	}
	set var(clock,$var(r)) [clock sec]
	set var(scandata) [split $data ""]
	parseScandata
}

# namespace ::rf
proc savePrefs {} {
}

# namespace ::rf
proc scr2freq x {
	variable var

	expr {860 + 2 * 10 * ($var(f1) + $x * 8) / 4000.0}
}

# namespace ::rf
proc setEventText args {
	variable var

	if {$args eq {}} {
		# user entered Return
		# extract the mark number tag
		regexp -- {M[0-9]+} [$var(scr) itemcget EE -tags] mark
		# set the text
		$var(scr) itemconfig [list $mark && Met] -text $var(edetxt)
		$var(scr) itemconfig EE -state hidden -tags EE

	} else {
		# some other action
	}
}

# namespace ::rf
proc toggleScan {} {

	variable var

	if {[string match "Sc*" $var(scanbtn)]} {
		portSetup
		set var(scanbtn) "Stop"
	} else {
		catch {
			chan close $var(port)
		}
		set var(scanbtn) "Scan"
	}
}

# namespace ::rf
proc updateCursors {x y} {
	variable var

	$var(scr) itemconfig clock -text [clock format $var(clock,$var(r)) -format %H:%M:%S]
	if {$x < 0 || $x >= $var(scan,W)} return
	# move horizontal cursor in spectrum analyzer
	if {$var(avgs,on)} {
		set rssi $var(fp,$x)
	} else {
		set rssi [lindex $var(scandata) $x]
	}
	set yrssi [expr {$var(sabase) - 15 * $rssi}]
	$var(scr) coords ycat -30 $yrssi
	$var(scr) itemconfig ycat -text "[format %0.1f [expr {$var(Pmin) + $var(RSstep) * $rssi}]]"
	$var(scr) coords ycal 0 $yrssi $x $yrssi
}
}; # end of namespace ::rf

proc ::main {} {
	::rf::init
}
##
main


