#!/usr/bin/tclsh8.6

## ------------------------------------------------------
## A software spectrum analyzer for the RF12B radio module
## (C) 2013, D.Zachariadis
## Licensed under the GPLv3
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

namespace eval ::mon {

# namespace ::mon
proc avgList list {
	if {![llength $list]} {return 0}
	expr double([join $list +])/[llength $list]
}

# namespace ::mon
proc bildBinds {} {
	variable var
	set W $var(scr)

	bind $W <Motion> [list [namespace current]::onEvent Motion %x %y %s]
	bind $W <1> [list [namespace current]::onEvent B1 %x %y %X %Y %s]
	bind $W <3> [list	[namespace current]::onEvent B3 %x %y %X %Y %s]
	bind $W <ButtonRelease-1> [list [namespace current]::onEvent B1R %x %y %s]
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
	bind $var(top) <<PortChanged>> [list [namespace current]::onChange port %d]
	bind $var(top) <<SettingsChanged>> [list [namespace current]::onChange %d]
	bind $var(top) <Control-1> [list [namespace current]::zoneSelect reset]
}

# namespace ::mon
proc buildCmdFieldWidget {W f data} {
	## builds a command field widget
	variable var
	set uw 4
	set fw 16
	set i 1
	set cnt 0
	lassign [split $f ,] field ctl
	pack [set w [::ttk::frame $W.f$f -padding {0 0}]] -anchor w -side top -fill x
	switch -glob -nocase -- [dict get $data type] {
		cho* {
			set vw 0
			set opts [dict keys [dict get $data opts]]
			# calculate width of combobutton
			foreach op $opts {
				if {[string match -* $op]} continue
				if {[string length $op] > $vw} {
					set vw [string length $op]
				}
			}
			set valwidg [::ttk::combobox $w.cb$f -textvariable [namespace current]::var(xcvr,$f) -values $opts -justify right -validate key -validatecommand {expr 0}]
			set vw [expr {$vw * 0.7}]
			if {$vw < 4} {set vw 4}
		}
		bool* {
			set vw 0
			set valwidg [::ttk::checkbutton $w.cbt$f -variable [namespace current]::var(xcvr,$f) -padding 0 -width 0]
		}
		scal* - entr* {
			set vw [string length [dict get $data def]]
			if {[string match "entr*" [dict get $data type]]} {
				set state "normal"
			} else {
				set state "readonly"
			}
			set valwidg [::ttk::spinbox $w.sb$f -textvariable [namespace current]::var(xcvr,$f) -from [dict get $data from] -to [dict get $data to] -increment [dict get $data incr] -justify right -validate key -validatecommand "
				[namespace current]::validateScalar %P
			"	-state $state]
		}
		func* {
			set valwidg [::ttk::label $w.t$f -anchor e -textvariable [namespace current]::var(xcvr,$f)]
			set vw [expr {21 - [string length [dict get $data desc]]}]
		}
	}
	set val [dict get $data def]
	if {[dict exists $data format]} {
		set var(xcvr,$f) [format [dict get $data format] $val]
	} else {
		set var(xcvr,$f) $val
	}
	# auto calculate  widget widths
	pack [::ttk::label $w.l$f -text "[dict get $data desc]:" -anchor w] -side left -anchor w
	pack [::ttk::label $w.u$f -text "[dict get $data units]" -width $uw -anchor w] -side right -anchor w
	$valwidg config -width [expr {round(([dict exists $data width] ? [dict get $data width] : $vw) * 0.9)}] -state [expr {[dict exists $data state]? [dict get $data state] : {}}]
	pack $valwidg -anchor w -side right
	incr cnt
}

# namespace ::mon
proc buildCmdWidget {W datavar ctl args} {
	# builds a widget in a labeled frame. The expected structure of the data is:
	# set var($var) {
	#		$ctl {
	#			cmd 0xdddd desc <string> def <value>
	#			field0 {
	#				lsb <n> 
	#				type ?choice | boolean | analog? 
	#				opts {name idx} 
	#			}
	#			field1 {...}
	#		}
	#	}
	variable var
	upvar $datavar data
	# we just need this control word, not all
	set control [dict get $data cmds $ctl]
	set uw 4
	set fw 16
	set i 1
	set cnt 0
	pack [set W [::ttk::frame $W.f$ctl -padding {5 5} -borderwidth 1 -relief ridge]] -anchor nw -padx 0 -side top -fill x -expand 1
	# choose only actual xcvr fields, in title format, not other data.
	foreach field [dict keys $control "\[A-Z]*"] {

		pack [set w [::ttk::frame $W.f$field -padding {0 0}]] -anchor w -side top -fill x
		switch -glob -nocase -- [dict get $control $field type] {
			cho* {
				set vw 0
				set opts [dict keys [dict get $control $field opts]]
				# calculate width of combobutton
				foreach op $opts {
					if {[string match -* $op]} continue
					if {[string length $op] > $vw} {
						set vw [string length $op]
					}
				}
				set valwidg [::ttk::combobox $w.cb$field -textvariable [namespace current]::var(xcvr,$ctl,$field) -values $opts -justify right -validate key -validatecommand {expr 0}]
				set vw [expr {$vw * 0.7}]
				if {$vw < 4} {set vw 4}
			}
			bool* {
				set vw 0
				set valwidg [::ttk::checkbutton $w.cbt$field -variable [namespace current]::var(xcvr,$ctl,$field) -padding 0 -width 0]
			}
			scal* - entr* {
				set vw [string length [dict get $control $field def]]
				if {[string match "entr*" [dict get $control $field type]]} {
					set state "normal"
				} else {
					set state "readonly"
				}
				set valwidg [::ttk::spinbox $w.sb$field -textvariable [namespace current]::var(xcvr,$ctl,$field) -from [dict get $control $field from] -to [dict get $control $field to] -validate key -validatecommand "
					[namespace current]::validateScalar %P
				"	-state $state]
			}
			func* {
				set valwidg [::ttk::label $w.t$field -anchor e -textvariable [namespace current]::var(xcvr,$ctl,$field)]
				set vw [expr {21 - [string length [dict get $control $field desc]]}]
			}
		}
		set val [dict get $control $field def]
		if {[dict exists $control $field format]} {
			set var(xcvr,$ctl,$field) [format [dict get $control $field format] $val]
		} else {
			set var(xcvr,$ctl,$field) $val
		}
		# auto calculate  widget widths
		pack [::ttk::label $w.l$field -text "[dict get $control $field desc]:" -anchor w] -side left -anchor w
		pack [::ttk::label $w.u$field -text "[dict get $control $field units]" -width $uw -anchor w] -side right -anchor w
		$valwidg config -width [expr {round($vw * 0.9)}]
		pack $valwidg -anchor w -side right
		incr cnt
	}
	update
	return $cnt
}

# namespace ::mon
proc buildConsole W {
	variable var

	# the console widget
	pack [set var(con) [text $W.con	-highlightcolor #246 -highlightthickness 1 -font {TkFixedFont -10} -height 1 -background #fff]] -fill both -side bottom -expand 1
	bind $var(con) <Key> [list [namespace current]::onConKey %K %s]

	pack [::ttk::frame $W.f1] -anchor nw -side bottom -fill x
	pack [::ttk::label $W.f1.conl -text "Console" -padding 0] -anchor w -side left
	pack [::ttk::checkbutton $W.f1.concb -text "Enable" -variable [namespace current]::var(con,on)] -side left
	pack [::ttk::button $W.f1.clrb -text "Clear" -command "
		$var(con) delete 0.0 end 
		after 10 [list focus $var(con)]
	" -padding 0 -style small.TButton -width 6] -side right
}

# namespace ::mon
proc buildControls W {
	variable var

	set lfpack {-side top -fill x -pady 0 -anchor nw}
	# create controls
	pack [::ttk::frame $W.pf] -fill x
	pack [::ttk::label $W.pf.portl -text "Port:" -padding 0] -anchor w -side left
	pack [::ttk::label $W.pf.hwl -text "" -textvariable [namespace current]::var(hw)] -side right -fill x
	pack [set var(port,wg) [::ttk::combobox $W.portcb -textvariable [namespace current]::var(portname) -values [enumerate ports] -postcommand "
		$W.portcb config -values \[[namespace current]::enumerate ports]
	"]] -anchor nw -fill x
	
	bind $W.portcb <<ComboboxSelected>> [namespace current]::portSetup
	bind $W.portcb <Return> [namespace current]::portSetup
	bind $W.portcb <KP_Enter> [namespace current]::portSetup
	
	pack [set w [::ttk::frame $W.scf -padding {2 5}]] -anchor nw
	pack [set var(scanb) [::ttk::checkbutton $w.scanb -style bold.TButton -text "Scan" -variable [namespace current]::var(scanning) -command [namespace current]::toggleScan -width 8 -padding {0 3}]] -anchor w -fill x -side left -padx 2
	pack [::ttk::button $w.clrb -text "Clear" -command [list [namespace current]::clear screen] -width 12 -padding {0 4}] -anchor w -fill x -side left -padx 1

	set w [::ttk::labelframe $W.spf -text "Spectrum:" -padding {5 2}]
	pack $w {*}$lfpack
	pack [::ttk::checkbutton $w.alcb -text "Auto contrast" -onvalue on -offvalue off -variable [namespace current]::var(alc,on) -width 15 -command "
		if {\$[namespace current]::var(evealc,on)} {
			[namespace current]::drawMark \"Auto contrast \$[namespace current]::var(alc,on)\" -tag 1
			set [namespace current]::var(maxrssi) 1
		}
	" -padding {0 0}] -anchor w -side top
	set wf [::ttk::frame $w.f1]
	pack $wf -anchor w
	pack [::ttk::checkbutton $wf.avgscb -text "Show avereges" -width 14 -variable [namespace current]::var(avgs,on) -padding 0 -command "
		if {\$[namespace current]::var(avgs,on)} {
			\$[namespace current]::var(scr) itemconfig asal -state {}
		} else {
			\$[namespace current]::var(scr) itemconfig asal -state hidden
		}
	"] -anchor w -side left
	pack [::ttk::spinbox $wf.avgsb -width 2 -from 1 -to 99 -increment 1 -textvariable [namespace current]::var(spec,avgln)] -anchor w -side left

	pack [::ttk::checkbutton $w.maxcb -text "Show max" -padding 0 -variable [namespace current]::var(maxs,on) -command "
		if {\$[namespace current]::var(maxs,on)} {
			\$[namespace current]::var(scr) itemconfig maxs -state normal
		} else {
			\$[namespace current]::var(scr) itemconfig maxs -state hidden
		}
	"] -anchor w -side top
	pack [::ttk::checkbutton $w.bwcb -text "Show RX bandwidth" -padding 0 -variable [namespace current]::var(bw,on) -command "
		if {\$[namespace current]::var(bw,on)} {
			\$[namespace current]::var(scr) itemconfig BWr -state normal
		} else {
			\$[namespace current]::var(scr) itemconfig BWr -state hidden
		}
	"] -anchor w -side top
	set wdth 7
	pack [::ttk::label $w.sll -text "Show signal strength:"] -anchor w -side top
	pack [::ttk::frame $w.of] -anchor w
	pack [::ttk::radiobutton $w.of.noslrb -text "Off" -value 0 -width $wdth -padding {8 0} -variable [namespace current]::var(sl,on)] -anchor w -side left
	pack [::ttk::radiobutton $w.of.cucb -text "Cursor" -value 1 -width $wdth -padding {8 0} -variable [namespace current]::var(sl,on)] -anchor w -side top
	pack [::ttk::frame $w.zo] -anchor w
	pack [::ttk::radiobutton $w.zo.chrb -text "Channel" -value 2 -width $wdth -padding {8 0} -variable [namespace current]::var(sl,on)] -anchor w -side left
	pack [::ttk::radiobutton $w.zo.zorb -text "Zone" -value 3 -width $wdth -padding {8 0} -variable [namespace current]::var(sl,on)] -anchor w -side left

	set w $W.mrkf
	pack [::ttk::labelframe $w -text "Marks:" -padding {5 2}] {*}$lfpack
	pack [::ttk::checkbutton $w.mklncb -text "Show mark lines" -variable [namespace current]::var(marklines,on) -command "
		if {\$[namespace current]::var(marklines,on)} {
			$var(scr) itemconfig Ml -state normal
		} else {
			$var(scr) itemconfig Ml -state hidden
		}
	" -padding 0] -anchor w
	pack [::ttk::label $w.automl -text "Auto mark changes of:" -padding {0 0}] -anchor nw
	pack [::ttk::checkbutton $w.pchcb -text "transceiver settings" -variable [namespace current]::var(evepch,on) -padding {15 0}] -anchor w
	pack [::ttk::checkbutton $w.alccb -text "auto contrast setting" -variable [namespace current]::var(evealc,on) -padding {15 0}] -anchor w
	set w $W.fcmd
	pack [::ttk::labelframe $w -text "Transceiver settings:" -padding {5 2}] {*}$lfpack
	pack [::ttk::checkbutton $w.sglcb -text "Set on change" -padding 0 -variable [namespace current]::var(sendi,on)] -anchor w
	pack [::ttk::frame $w.sndf] -fill x -pady 3
	pack [::ttk::button $w.sndf.sndb -text "Set" -padding {0 3} -width 8 -state disabled -style bold.TButton -command "
	"] -anchor w -padx 0 -pady 0 -side left
	pack [::ttk::button $w.sndf.prnb -text "Print" -padding {0 4} -width 8 -command "
		[namespace current]::print
	"] -anchor w -padx 5 -pady 0 -side left
	buildXmit $W
	buildConsole $W
}

# namespace ::mon
proc buildPopup {{W .mon}} {
	variable var
	#popup window
	catch {
		destroy $W.popup
	}
	set var(popup) [menu $W.popup -bg #f0f0f0 -bd 1 -tearoff 0  -activeborderwidth 0 -font {TkDefaultFont -11}  -postcommand {} -relief raised -tearoff 0 -title "Commands"]

	$var(popup) add command -label "Mark time" -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark TMark \$x \$y
	"
	$var(popup) add command -label "Mark freq." -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark FMark \$x \$y
	"
	$var(popup) add command -label "Mark event" -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark Event \$x \$y
	"
	$var(popup) add command -label "Mark port" -command "
		lassign \$[namespace current]::var(popup,xy) x y
		[namespace current]::mark Port \$x \$y
	"
	$var(popup) add separator
	$var(popup) add command -label "Limit scan width" -command [list [namespace current]::zoneSelect start]
	$var(popup) add command -label "Full scan width" -command [list [namespace current]::zoneSelect reset]
	$var(popup) add separator
	$var(popup) add command -label "Clear mark" -command [list [namespace current]::editMark Delete]
	$var(popup) add command -label "Clear marks" -command [list [namespace current]::clear marks]
	$var(popup) add command -label "Clear all" -command [list [namespace current]::clear all]
}

# namespace ::mon
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
	foreach {p ww} {name 15 speed 8 desc 20 use 0} {
		pack [::ttk::label $w.tf.[string range $p 0 1]l -text $p -width $ww] -side left -anchor w
	}
	set i 1
	foreach p [enumerate ports] {
		pack [::ttk::frame $w.line$i] -fill x
		pack [::ttk::label $w.line$i.pl -text $p -width 15] -side left
	pack [::ttk::combobox $w.line$i.cb -textvariable [namespace current]::var(portspeed) -values [set [namespace current]::var(portspeeds)] -width 6] -anchor w -side left
		pack [::ttk::entry $w.line$i.pe -width 20 -textvariable [namespace current]::var(port,desc,$p)] -side left
		set [namespace current]::var(port,use,$p) 1
		pack [::ttk::checkbutton $w.line$i.pu -variable [namespace current]::var(port,use,$p) -padding 2] -side left -anchor c
		incr i
	}
}

# namespace ::mon
proc buildQuickSettings W {
	variable var

	set w $W.qf
	::ttk::frame $w -style light.TFrame
	$W add $w -text "Quick settings"
	## the Quick Settings pane contains selected fields from various commands
	set i 0
	set x 0
	foreach {t fs} {
		Receiver {FSC,Freq FSC,F CSC,FB RCC,BW RCC,LNA RCC,RSSI}
		Transmitter {TXC,Pwr TXC,M DRC,R DRC,BR DRC,DBR PLL,Bw0 }
		{Data filter & AFC} {DFC,Al DFC,Ml DFC,DQD AFC,A AFC,Rl AFC,Fi}
		RfMon {rfMon,Id SP,B rfMon,Ack rfMon,Zw}
	} {
		## create a container for the fields
		place [set lf [::ttk::frame $w.f$i-$x -borderwidth 1 -relief ridge -padding 5]] -x $x -y 0 -width 210 -height 132
		## insert the fields in the container
		foreach f $fs {
			lassign [split $f ,] C field
			buildCmdFieldWidget $lf $f [dict get $var(rf12b) cmds $C $field]
		}
		incr x 210
	}
}

# namespace ::mon
proc buildScreen W {
#	variable var
	variable var

	pack [canvas $W -background black -width $var(c,W) -height $var(c,H) -xscrollincrement 1 -yscrollincrement 1] -side top -anchor nw -fill x
	# to ease positioning on the canvas, we'll keep the upper left origin and create the margins by shifting the canvas down and to the right
	$W xview scroll -$var(left,margin) u
	$W yview scroll -$var(top,margin) u
	# create event deleting widget image
	catch {image delete [namespace current]::clr}
	image create photo [namespace current]::clr -data {
R0lGODlhDQAMAIQQAAABABIUESYoJU9RTlhaV2RlY3Z4dY2PjJWXlJ2fnKWn
pNTX0+Di3+bo5efp5vz++///////////////////////////////////////
/////////////////////////yH5BAEKAAwALAAAAAANAAwAAAVCIPOITFmO
Y7kUCaoUi/kMANAm9ZA+Rg0cPkNKRPDVCMMTLZdU+nSmU9GIlBV8wFohtfAp
HgpfTCT4oYCC4aOhdqRCADs=
}
# create cursor image
	catch {image delete [namespace current]::cross}
image create photo [namespace current]::cross -data {
R0lGODlhDwAPAIABAMzMzAAAACH5BAEKAAEALAAAAAAPAA8AAAIYjI+pAbvt
Eoxn0osN2JbxDF5dNDrlEy4FADs=
}
	# mark editing entry widget, initially hidden
	::ttk::frame $W.edf
	set var(evente) [::ttk::entry $W.edf.ede -width 15 -font {TkDefaultFOnt -9} -textvariable [namespace current]::var(edetxt)]
	pack $var(evente) -side left -anchor w
	pack [::ttk::button $W.edf.clr -image [namespace current]::clr -padding 0 -command "
		[namespace current]::editMark delete
	"] -side left -anchor w
	set var(eventi) [$W create window 0 480 -window $W.edf -tags {EE fx NO} -state hidden -anchor w]

	# waterfall blank image
	set var(wfi) [image create photo [namespace current]::wf]
	$var(wfi) config -width $var(wf,W) -height $var(wf,H)
	# black backround
	$var(wfi) put #000 -to 0 0 $var(wf,W) $var(wf,H)
	# put waterfall image on the screen canvas
	$W create image 0 0 -image $var(wfi) -anchor nw -tags {wfi fx NO}
	# put the image cursor on the canvas but hide it
	$W create image 0 0 -image [namespace current]::cross -anchor center -tags {cross fx NO}
	# create the specraline 
	$W create line 0 0 0 0 -fill #f60 -tags {SL fx NO}
	drawScreen $W
	bind $W <<ValueChange>> "[namespace current]::onValueChange %d"
}

# namespace ::mon
proc buildSettings W {
	variable var

	::ttk::frame $W.f
	$W add $W.f -text "Transceiver settings"
	set w $W.f

	pack [::ttk::scrollbar $w.vsb -orient vertical -command [list $w.xcvrf yview]] -side right -fill y
	pack [set c [canvas $w.xcvrf -background #eceae5 -yscrollcommand [list $w.vsb set] -xscrollincrement 1 -yscrollincrement 1]] -fill both -expand 1
	bind $w.vsb <Button-4> {event generate %W <<MouseWheel>> -data 120 -x %x -y %y -state %s; break}
	bind $w.vsb <Button-5> {event generate %W <<MouseWheel>> -data -120 -x %x -y %y -state %s; break}
	bind $w.vsb <<MouseWheel>> "[namespace current]::onPanelEvent %W $c Wheel %x %y %s %d;	break"
	# position widgets on the 'Transceiver Settings' panel
	lassign {0 0 0} x y curcol
	array set col {x,0 0 x,1 205 x,2 410 x,3 615 y,0 0 y,1 0 y,2 0 y,3 0}
	foreach C [dict keys [dict get $var(rf12b) cmds]] {
		if {![string match "\[A-Z]*" $C] || [dict keys [dict get $var(rf12b) cmds $C] "\[A-Z]*"] eq {}} continue
		pack [set lf [::ttk::frame $c.f$C -borderwidth 1 -relief ridge -padding 0]]
		pack [::ttk::frame $lf.tf -padding 0] -fill x
		pack [::ttk::label $lf.tf.lfl -text [dict get $var(rf12b) cmds $C desc] -width 21 -anchor w] -anchor nw -side left
		pack [::ttk::button $lf.tf.lcmd -textvariable [namespace current]::var(xcvr,$C) -width 6 -style smallBold.TLabel -padding 0 -command "
			[namespace current]::con \"[dict get $var(rf12b) cmds $C desc]:\\t\$[namespace current]::var(xcvr,$C)\\n\"
		"] -anchor sw -side right
		foreach wg {.tf .tf.lfl .tf.lcmd} {
			bind $lf$wg <Button-1> "[namespace current]::onPanelEvent %W $c B1 %x %y %s $C"
			bind $lf$wg <Button1-Motion> "[namespace current]::onPanelEvent %W $c B1M %x %y %s $C"
			bind $lf$wg <ButtonRelease-1> "+[namespace current]::onPanelEvent %W $c B1R %x %y %s $C"
		}
		buildCmdWidget $lf [namespace current]::var(rf12b) $C horiz
		# find the shortest column and its y size
		set curcol 0
		for {set i 1} {$i < 4} {incr i} {
			if {$col(y,$curcol) > $col(y,$i)} {set curcol $i}
		}
#		lassign [split [lindex [lsort -integer -stride 2 -index 1 [array get col y,*]] 0] ,] _ curcol
		set y $col(y,$curcol)
		incr y 5
		lassign [split [winfo geo $lf] x+] width height
		$c create window $col(x,$curcol) $col(y,$curcol) -anchor nw -window $lf -tags [list W $C $lf]
		update
		set col(y,$curcol) [expr {$col(y,$curcol) + $height + 5}]
		set curcol [expr {($curcol + 1) % 4}]
	}
	set var(panel) $c
	lassign [$w.xcvrf bbox all] x y e s
	$w.xcvrf configure -scrollregion [list -3 -5 $e $s]
	$w.xcvrf yview moveto 0.0

	buildQuickSettings $W

	::ttk::frame $W.monsetf -padding 0
	$var(setnb) add $W.monsetf -text "RfMon settings"
	# select the 'quick settings' panel
	$W select 1
}

# namespace ::mon
proc buildTop {{W .mon}} {
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
	set var(top) $W
	wm title $W $var(title)
	wm geometry $W $var(win,W)x$var(win,H)
	wm protocol $W WM_DELETE_WINDOW [namespace current]::quit
	wm resizable $W 0 1
	::ttk::style theme use clam
	::ttk::style configure bold.TButton -font {TkDefaultFont -14 bold} -foreground #222
	::ttk::style configure boldRed.TButton -font {TkDefaultFont -14 bold} -foreground #800
	::ttk::style configure TCombobox -foreground #00f
	::ttk::style config TSpinbox -padding {4 0 4 0} -arrowsize 8 -foreground #00f
	::ttk::style config TCheckbutton -padding 0
	::ttk::style config smallBold.TLabel -font {TkDefaultFont -10 bold}
	::ttk::style config bold.TLabel -font {TkDefaultFont -11 bold}
	::ttk::style config light.TFrame -background #eee
	::ttk::style config red.TCombobox -fieldbackground #f88
	::ttk::style config green.TCombobox -fieldbackground #8f8
	
	font configure TkDefaultFont -size -11
	font configure TkTextFont -size -11

	# main sections of top window
	# left section
	pack [::ttk::frame $W.lf] -side left -expand 1 -fill both -anchor nw
	# top left section, the screen canvas
	set var(scr) $W.lf.c
	buildScreen $var(scr)

	# bottom top section, the settings
	pack [set var(setnb) [::ttk::notebook $W.lf.setnb]] -fill both -expand 1
	# general tools and parameters
	buildSettings $var(setnb)
	# right section
	pack [::ttk::frame $W.rf -relief ridge -borderwidth 1 -padding 3] -side top -expand 1 -fill both
	# screen controls and command/log window
	buildControls $W.rf
	update

	# other necessities
	buildPopup
	bildBinds
}

# namespace ::mon
proc buildXmit W {
	variable var
	pack [set w [::ttk::labelframe $W.xmitf -text "Transmission:" -padding {5 2} -labelanchor nw]] -anchor nw -pady 2 -fill x -side top
	pack [::ttk::frame $w.f1 -padding {0 1}] -anchor w -fill x
	pack [::ttk::label $w.f1.xmodl -text "Mode:" -width 5 -anchor w] -side left -anchor w
	pack [::ttk::combobox $w.f1.xmodcb -textvariable [namespace current]::var(txtype) -values {CW} -width 4 -justify right] -anchor w -side left
	pack [::ttk::label $w.f1.durl -text " Dur:" -width 4 -anchor w] -side left -anchor w
	pack [::ttk::combobox $w.f1.durcb -textvariable [namespace current]::var(txdur) -values {1 5 10 30 60 90 120 150} -width 3 -justify right] -anchor w -side left

	pack [::ttk::button $w.xmitb -style boldRed.TButton -text "Transmit" -command [namespace current]::xmit -textvariable [namespace current]::var(xmitting) -width 16 -padding {0 3}] -anchor center -pady 3 -side top
}

# namespace ::mon
proc chan2freq {ch {b {}}} {
	variable var
	if {$b eq ""} {
		set b $var(xcvr,band)
	}
	expr {10 * [dict get $var(rf12b) bands $b c1] * ([dict get $var(rf12b) bands $b c2] + $ch/4000.0)}
}

# namespace ::mon
proc clear what {
	variable var

	switch -glob -- $what {
		"scr*" -	"all" {
			$var(wfi) put #000 -to 0 0 480 300
			$var(scr) coords csal 0 0 0 0
			$var(scr) coords asal 0 0 0 0
			$var(scr) delete M E
			initFreqArray
		}
		"marks" {
			$var(scr) delete M E
		}
	}
}

# namespace ::mon
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

# namespace ::mon
proc colors {colors args} {
	# given the number of desired colors, return a palette of colors, given a series of coordinates for an intensity curve
	set step [expr {round(255.0 / $colors)}]
	set palette {}
	set args [lassign $args x1 y1]
	foreach {x2 y2} $args {
		set a [expr {double($y2-$y1)/($x2-$x1)}]
		for {set x $x1} {$x1 <= $x && $x <= $x2} {incr x $step} {
			set y [expr {round($a * ($x - $x1) + $y1)}]
			lappend palette $y
		}
		set x1 $x2
		set y1 $y2
	}
#	lappend palette [format %02x $y2]
	return $palette
}

# namespace ::mon
proc con {s {prompt 0}} {
	variable var
	if {! $var(con,on)} return
	
	$var(con) insert end $s
	$var(con) see end
	# when to print the prompt?
	# 1. if user just hits enter
	# 2. if we are specifically told so
	# The caller should know if it's finished with printing to the console and ask for a prompt
	if {![string length [string trim $s]] || $prompt} {
		prompt
	}
}

# namespace ::mon
proc createDimensions wfw {
	variable var
	set gr 1.618
	set wfh [expr {round($wfw / $gr)}]
	set ch [expr {$wfw + $var(top,margin) + $var(bottom,margin)}]
	set sah [expr {$wfw - $wfh}]
	set cw [expr {round($wfw + $wfh + $var(mark,margin))}]
	set toph [expr {$ch + $var(mark,margin)}]
	return [list wf,W $wfw wf,H $wfh sa,H $sah sa,base $wfw c,W $cw c,H $ch win,W [expr {round($toph * $gr)}] win,H $toph sl,end [expr {$wfw + $sah + $var(sl,left)}]] 
}

# namespace ::mon
proc createXceiverObject name {
	variable var
::oo::class create xcvr {
	constructor args {}
	destructor {}
}
}

# namespace ::mon
proc cursor2event {tag tags} {
	variable var
	# arrow
	$var(scr) create line [$var(scr) coords ${tag}a] {*}[dict merge [opts2dict $var(scr) ${tag}a] [list -tags [concat $tags Mal] -fill #fff]]
	# frequency
	set coords [$var(scr) coords ${tag}t]
	$var(scr) create text $coords {*}[dict merge [opts2dict $var(scr) ${tag}t] [list -tags [concat $tags Mt] -fill #fff]]
	if {$tag eq "tc"} {
		$var(scr) create text $var(mark,start) [lindex $coords 1] {*}[dict merge [opts2dict $var(scr) ${tag}t] [list -tags [concat $tags Met] -fill #fff -text "Mark $var(markcnt)" -anchor w]]
	}
	# frequency line
	$var(scr) create line [$var(scr) coords ${tag}l] {*}[dict merge [opts2dict $var(scr) ${tag}l] [list -tags [concat $tags Ml] -fill #222]] -state [expr {$var(marklines,on) ? "normal" : "hidden"}]
}

# namespace ::mon
proc deleteMark r {
	variable var

	unset -nocomplain var(M,mark)
	$var(scr) del r$var(r)
}

# namespace ::mon
proc disableTrace avar {
	variable var

	if {$avar eq {}} {
	}
}

# namespace ::mon
proc drawAxis {W args} {
	# draw an axis on canvas W, data is canvas related except for -startval and -endval
	set data [dict merge {-axisx 0 -axisy 0 -minsep 25 -orient horizontal -size 300 -startval 0 -endval 300 -stepval 1} $args]
	if {[string match -nocase "h*" [dict get $data -orient]]} {
		set axs [dict get $data -axisx]
	} else {
		set axs [dict get $data -axisy]
	}
	set dp $axs
}

# namespace ::mon
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

# namespace ::mon
proc drawGrid W {
	variable var

	# minimum separation of grid lines to be redable
	set minxsep 25
	set fs 1 ; # frequency step
	# hide items that may interfere with grid
	$W itemconfig [list BW] -state hidden
	$W delete g
	set lf [expr {int(ceil([chan2freq [dict get $var(rf12b) lch]]))}]
	set uf [expr {int(floor([chan2freq [dict get $var(rf12b) uch]]))}]

	set dp 0
	for {set f $lf} {$f <= $uf} {incr f $fs} {
		set d [freq2scr $f]
		if {$d >= ($dp + $minxsep)} {
			$W create line $d 0 $d $var(sa,base) -fill #222 -tags [list g gx gxl g$d fx] -dash {2 2}
			set ti [$W create text $d [expr {$var(sa,base) + 5}] -anchor n -text $f -tags [list g gt gxt g$d fx] -fill #666 -font {TkDefaultFont -10}]
			# if despite our efforts our new grid text overlaps with something, then delete it
			if {[$W find overlapping {*}[$W bbox $ti]] ne $ti} {
				$W delete $ti
			}
			set dp $d
		}
		$W create line $d $var(sa,base) $d [expr {$var(sa,base) + 5}] -fill #222 -tags [list g gx gxl gxtc g$d fx]
	}
	# y axis dB
	set dp $var(sa,base)
	for {set dBm  $var(RSstep)} {$dBm < $var(RSr)} {incr dBm $var(RSstep)} {
		set d [expr {$var(sa,base) - $var(sa,dBppx) * $dBm}]
		if {$d >= ($dp - $minxsep)} {
			$W create line 0 $d $var(wf,W) $d -fill #222 -tags [list g gy gyl g$d fx] -dash {2 2}
			$W create text -5 $d -anchor e -text [expr {$var(Pmin) - $var(RSstep) + $dBm}] -tags [list g gt gyt g$d fx] -fill #666 -font {TkDefaultFont -10}
			set dp $d
		}
		$W create line 0 $d -5 $d -fill #222 -tags [list g gy gyl gytc g$d fx]
	}
	# x axis dB
	set dp 0
	for {set dBm $var(RSstep)} {$dBm < $var(RSr)} {incr dBm $var(RSstep)} {
		set d [expr {$var(sl,start) + $var(sa,dBppx) * $dBm}]
		if {$d >= ($dp + $minxsep)} {
			$W create line $d 0 $d $var(sa,top) -fill #222 -tags [list g gx gxl g$d fx] -dash {2 2}
			$W create text $d [expr {$var(sa,top) + 5}] -anchor n -text [expr {$var(Pmin) - $var(RSstep) + $dBm}] -tags [list g gt gxt g$d fx] -fill #666 -font {TkDefaultFont -10}
			set dp $d
		}
		$W create line $d $var(sa,top) $d [expr {$var(sa,top) + 5}] -fill #222 -tags [list g gx gxl gxtc g$d fx]
	}
		$W itemconfig [list BW] -state normal

}

# namespace ::mon
proc drawMark {txt args} {
	variable var

	if {![dict exists $args -r]} {
		set r  $var(r)
	} else {
		set r [dict get $args -r]
	}
	if {[dict exists $args -tags]} {
		set tags [dict get $args -tags]
	} else {
		set tags {}
	}
	incr var(markcnt)

	$var(scr) create line 0 $r $var(sl,end) $r -dash {2 2} -fill #333 -tags [list M Ml Mhl r$r M$var(markcnt)]
	set itxt [$var(scr) create text [expr {$var(sl,end) + 2}] $r -text $txt -fill #fff -font {TkDefaultFont -11} -anchor w -tags [concat M Mt Met r$r M$var(markcnt) $tags]]

	if {[info exists var(clock,$r)]} {
		$var(scr) create text -3 $r -text "[clock format [expr {$var(clock,$r)/1000}] -format %H:%M:%S][string range [expr {fmod($var(clock,$r)/1000.0,1)}] 1 3]" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list M T Mt r$var(r) M$var(markcnt)]
	}
}

# namespace ::mon
proc drawRxBW {W args} {
	variable var
	
	set x [freq2scr $var(xcvr,FSC,Freq)]
	set var(lbw) [freq2scr [expr {$var(xcvr,FSC,Freq) - $var(xcvr,RCC,BW)/2000.0}]]
	set var(ubw) [freq2scr [expr {$var(xcvr,FSC,Freq) + $var(xcvr,RCC,BW)/2000.0}]]
	if {0 > $var(ubw) || $var(lbw) > $var(wf,W)} {
		$W itemconfig BWr -state hidden
	} elseif {$var(bw,on)} {
		$W itemconfig BWr -state normal
	}
	$W coords BWr $var(lbw) 0 $var(ubw) $var(sa,base)
	$W coords BWa $x [expr {$var(sa,base) + 6}] $x $var(sa,base)
}

# namespace ::mon
proc drawScanline {} {
	variable var

	if {$var(hold)} return
	set r $var(r)
	# delete events from previous scans on this row
	editMark delete $var(r)
	# don't draw line if it contains non numbers
	if {[catch {
		set maxrssi [::tcl::mathfunc::max {*}$var(scandata)]
	}]} {
		return
	}
	# calculate maxrs to use in case ALC is on
	if {!$var(alc,on) || $maxrssi > $var(RSlev)} { 
		# prevent overruns of color array
		set maxrs $var(RSlev)
	} else {
		# avoid a maxrssi of 0, avoids division by 0 errors
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
	# save a division by not doing it in the loop
	set rrssi [expr {$maxrs ? $var(RSlev) / double($maxrs) : 1}]
	lassign {} scanline maxs
	set sig {}
	set len [llength $var(scandata)]
	set len [expr {$len < $var(wf,W) ? $len : $var(wf,W)}]
	# move current scan line
	$var(scr) coords cscl $var(scan,start) [expr {$r + 2}] [expr {$var(scan,start) + $len}] [expr {$r + 2}]

	set coords [list $var(scan,start) $var(sa,base)]
	for {set i 0} {$i < $len} {incr i} {
		set ovrld {}
		set rssi [lindex $var(scandata) $i]
		if {![string is integer -strict $rssi]} {
			set rssi 0
		}
		#
		if {$rssi > $var(RSlev)} {
			set rssi $var(RSlev)
			lappend ovrld $i
		} elseif {$rssi && ($rssi == $maxrssi)} {
			lappend maxs $i
		}
		if {$ovrld ne {}} {
			# draw pixel in overload color
			lappend scanline #f88
		} else {
			lappend scanline $var(wfcolor,[expr {int($rrssi * $rssi)}])
		}
		# current frequency point
		lappend coords [expr {$var(scan,start) + $i}] [expr {$var(sa,base) - $var(sa,RSpxps) * $rssi}]
		# average freq points
		set var(fp,$i) [expr {($var(fp,$i)*($var(spec,avgln) - 1) + double($rssi)) / $var(spec,avgln)}]
		if {($var(lbw) - $var(scan,start)) <= $i && $i <= ($var(ubw) - $var(scan,start))} {
			# freq lies within the receiver's bandwidth
			lappend sig $rssi
		}
	}

	set var(sig,$var(r)) [avgList $sig]
	# plot current spectrum line
	lappend coords [expr {$var(scan,start) + $len}] $var(sa,base)
	$var(scr) coords csal $coords
	# plot avg spectrum line
	if {$var(avgs,on)} {
		set coords [list $var(scan,start) $var(sa,base)]
		for {set i 0} {$i < $len} {incr i} {
			lappend coords [expr {$var(scan,start) + $i}] [expr {$var(sa,base) - $var(sa,RSpxps) * $var(fp,$i)}]
		}
		lappend coords [expr {$var(scan,start) + $i}] $var(sa,base)
		$var(scr) coords asal $coords
	}
	# draw waterfall spectrum line
	$var(wfi) put [list $scanline] -to $var(scan,start) $var(r)
	# draw maxrssi
	$var(scr) itemconfig maxrssi -text "[expr {round($var(Pmin) + $var(RSstep) * $maxrssi)}] dBm"
	set y [expr {$var(sa,base) - $var(sa,RSpxps) * $maxrssi}]
	$var(scr) coords maxrssi $var(right,margin) $y
	$var(scr) del maxs ovrld
	foreach m $maxs {
		$var(scr) create rect [expr {$var(scan,start) + $m - 3}] [expr {$y - 3}] [expr {$var(scan,start) + $m + 3}] [expr {$y + 3}] -tags maxs -outline #8f4 -state [expr {$var(maxs,on)? "normal" :"hidden"}]
	}
	foreach m $ovrld {
		$var(scr) create rect [expr {$m - 2}] [expr {$y - 2}] [expr {$m + 2}] [expr {$y + 2}] -tags maxs -outline #f00 -fill #f00
	}
	# store scanned lines per second
	set var(mspl) [expr {($var(clock,$var(r)) - $var(clock0))}]
	$var(scr) itemconfig mspl -text "$var(mspl) ms"
	set var(clock0) $var(clock,$var(r))
	set x [expr {int([$var(scr) canvasx $var(sx)])}]
	updateCursors $x [expr {int([$var(scr) canvasy $var(sy)])}]
}

# namespace ::mon
proc drawScreen W {
	variable var

	set satop [expr {$var(wf,H) + 0 + 5}]
	set ttcolor #ccc

	$W del [list ! NO]
	# section borders
	$W create line 0 -$var(top,margin) 0 $var(c,H) -tags [list st stv fx] -fill #444
	$W create line -500 0 $var(c,W) 0 -tags [list st sth fx] -fill #444
	$W create line $var(wf,W) -$var(top,margin) $var(wf,W) $var(c,H) -tags [list st stv fx] -fill #444
	$W create line -500 $var(wf,H) $var(c,W) $var(wf,H) -tags [list st sth fx] -fill #444
	$W create line [expr {$var(sl,start) + $var(sa,H)}] -$var(top,margin) [expr {$var(sl,start) + $var(sa,H)}] $var(wf,H) -tags [list st stv fx] -fill #444

	$W create text -50 -10 -text "Time" -anchor sw -font {TkDefaultFont -10 bold} -fill $ttcolor -tags {tmt fx tt}
	$W create text -58 -5 -text "" -anchor w -font {TkDefaultFont -9} -fill #666 -tags {clock fx}
	$W create text [expr {$var(wf,W) + 5}] -10 -text "dBm" -anchor sw -fill #444 -tags {hzt fx} -font {TkDefaultFont -12 bold}

	$W create text -50 [expr {$var(wf,H) + 0 + 5}] -text "dBm" -anchor nw -font {TkDefaultFont -10 bold} -fill $ttcolor -tags {gat fx tt}
	$W create text 5 -10 -text "MHz" -anchor sw -fill #444 -tags {hzt fx} -font {TkDefaultFont -12 bold}
	$W create text [expr {$var(c,W) - $var(left,margin) - 10}] 5 -text "Events" -anchor ne -fill $ttcolor -tags {evt fx tt} -font {TkDefaultFont -11 bold}
	$W create text [expr {$var(c,W) - $var(left,margin) - 76}] -3 -anchor se -text "Rf" -fill #88f -tags {RFmon Rf fx NO} -font {TkDefaultFont -14 bold}
	$W create text [expr {$var(c,W) - $var(left,margin) - 40}] -3 -anchor se -text "mon" -fill #f80 -tags {RFmon mon fx NO} -font {TkDefaultFont -14 bold}
	$W create text [expr {$var(c,W) - $var(left,margin) - 5}] -3 -anchor se -text $var(version) -fill #444 -tags {RFmon mon fx NO} -font {TkDefaultFont -12 bold}
	$W create text [expr {$var(c,W) - $var(left,margin) - 10}] [expr {$var(wf,H) + 0 + 5}] -text "Spectrum" -anchor ne -fill $ttcolor -tags {sat fx tt} -font {TkDefaultFont -11 bold}
	drawGrid $W
	# vertical x cursor
	set ty [expr {-11 - 9 * ($var(markcnt) %2)}]
	set x 0
	set tx [expr {$x + 6}]
	$W create line $tx $ty $x $ty $x 0 -arrow last -arrowshape {6 7 3} -fill #ffffff -tags [list xc xca fx c]
	$W create text $tx $ty -text [format " %0.2f GHz" [expr {($var(lch) + $x * $var(scale))/1000.0}]] -fill #fff -font {TkDefaultFont -9} -anchor w -tags [list xc xct fx c]
	$W create line $x 0 $x $var(c,H) -fill #444 -tags [list xc xcl fx c]
	# horizontal raw cursor 
	$W create line 0 0 0 0 -fill #444 -dash {2 2} -tags [list yc yccl fx c] 
	$W create text -5  $var(c,H) -text "" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list yc yct fx c]
	# horizontal avg cursor 
	$W create line 0 0 0 0 -fill #444 -dash {2 2} -tags [list yc ycl ycal fx c]
	$W create text -5  $var(c,H) -text "" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list yc yct ycat fx c]
	# time cursor
	$W create line 0 0 0 0 -fill #fff -tags [list tc tca fx c] -arrow last -arrowshape {6 7 3}
	$W create line 0 0 0 0 -tags {tc tcl fx c} -dash {2 2} -fill #444
	$W create text -5  0 -text "" -fill #fff -font {TkDefaultFont -9} -anchor e -tags [list tc tct fx c]
	$W itemconfig [list xcl || ycl] -dash {2 2}
	# spectrum lines
	$W create poly 0 0 0 0 -fill #88f -tags {sa csa csal}
	$W create line 0 0 0 0 -fill #c63 -tags {sa asa asal}
	$W create text -30 [expr {$var(sa,base) + 10}] -anchor ne -fill #88f -font {TkDefaultFont -10} -text "Raw" -tags {sa csa csat} 
	$W create text -10 [expr {$var(sa,base) + 10}] -anchor ne -fill #f84 -font {TkDefaultFont -10} -text "Avg" -tags {sa asa asat}
	$W create text [expr {$var(wf,W) + 5}] $var(sa,base) -anchor w -fill #fff -font {TkDefaultFont -10} -text "$var(Pmin) dBm" -tags {maxrssi}
	# spectrum x axis
	$W create line 0 $var(sa,base) $var(wf,W) $var(sa,base) -tags [list sax fx] -fill #222
	# milliseconds per line
	$W  create text [expr {$var(c,W) - $var(left,margin) - 10}] [expr {$satop + 20}] -text ms -tags {mspl fx} -anchor e -font {TkFixedFont -10} -fill #666
	# bandwidth rect
	$W create rect 0 0 0 0 -outline #030 -tags {BW BWr fx NO} -dash {1 2}
	$W create line 0 0 0 0 -fill #0f0 -tags {BW BWa fx NO} -width 3
	# create current scan line
	$W create line 0 0 $var(wf,W) 0 -tags {cscl NO} -fill #800 -width 2
	$W raise cross
}

# namespace ::mon
proc editMark {e {row {}}} {
	variable var

	switch -nocase -glob -- $e {
		"edit" {
			lassign $var(popup,xy) x y tags
			# get mark number and row
			set tag [regexp -inline -- {M[0-9]+} $tags]
			regexp -- {r([0-9]+)} $tags _ r
			lassign [$var(scr) bbox [list $tag && Met]] w n e s
			# ... and use them to place the entry widget
			$var(scr) coords EE $var(mark,start) $r
			set var(edetxt) [$var(scr) itemcget [list $tag && Met] -text]
			$var(scr) itemconfig EE -state normal -tags [list EE R$r $tag]
			$var(evente) select range 0 end
			focus $var(evente)
		}
		"del*" {
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

# namespace ::mon
proc enumerate what {
	variable var

	switch -glob -nocase -- $what {
		"ports" {
			lappend out {*}[glob -nocomplain /dev/ttyUSB* /dev/ttyACM*]
			if {[llength $out]} {
				set out [concat {{}} $out]
			}
			lappend out "disconnect"
		}
		"txpow*" {
			return [dict keys [dict get $var(rf12b) txpower]]
		}
		"band" {
			foreach b [dict keys [dict get $var(rf12b) bands]] {
				lappend out [chan2freq 1600 $b]
			}
			return $out
		}
	}
}

# namespace ::mon
proc enumerateCmd {{cmd *}} {
	## loop through controls returning one at a time
	variable var

	if {[info command [namespace current]::cmdco] eq {}} {
		## create coroutine to loop through all controls
		return [coroutine [namespace current]::cmdco apply "cmd {
			# coroutine body
			foreach {C dat} \[dict filter \[dict get \[[namespace current]::xcvrData] cmds] key \$cmd]  {
				if {\$cmd eq {*}} {
					yield \[list \$C \$dat]
				} else {
					dict for {f d} \$dat { yield \[list \$C \$f \$d] }
				}
			}
		}" $cmd]
	}
	## coroutine is already running, return next cotrol
	cmdco
}

# namespace ::mon
proc freq2chan {f {b {}}} {
	variable var

	if {$b eq {}} {
		set b $var(xcvr,band)
	}
	expr {round(($f / 10.0 / [dict get $var(rf12b) bands $b c1] - [dict get $var(rf12b) bands $b c2]) * 4000.0)}
}

# namespace ::mon
proc freq2chband f {
	variable var

	## enumerate band indices
	set bands [dict keys [dict get $var(rf12b) bands]]
	## find and set the band this frequency is in
	foreach b $bands {
		## check if the entered frequency lies within the lower and upper limits of this band
		if {	[chan2freq [dict get $var(rf12b) lch] $b] <= $f && 
				$f < [chan2freq [dict get $var(rf12b) uch] $b]
		} {
			## find the channel that corresponds to this frequency in this band
			set ch [freq2chan $f $b]
			set band [dict get $var(rf12b) bands $b name]
			## since we've found the band, there is no need to search more
			break
		}
	}
	## what if the frequency entered was outside the limits of the bands this xceiver is capable of handling?
	if {![info exists ch]} {
		## set the default band and channel so the receiver can operate
		set CSC [dict get $var(rf12b) cmds CSC]
		# find default band index
		set b [dict get $CSC FB opts [dict get $CSC FB def]]
		# get default band name
		set band [dict get $var(rf12b) bands $b name]
		# get default channel
		set ch [dict get $var(rf12b) cmds FSC F def]
	}
	return [list $band $ch $b]
}

# namespace ::mon
proc freq2scr f {
	variable var
	# f0 = 10 * c1 * (c2 + F/4000) MHz , 433 {c1 1 c2 43} 868 {c1 2 c2 43} 915 {c1 3 c2 30}
	expr {([freq2chan $f] - [dict get $var(rf12b) lch]) / $var(scale)}
}

# namespace ::mon
proc getSignalLine x {
	variable var

	set out {}
	for {set y 0} {$y < $var(wf,H)} {incr y} {	
		if {$var(sl,on) == 1} {
			lappend out [avgList [$var(wfi) get $x $y]]
		} else {
			lappend out [expr {$var(sig,$y) * ($var(sa,H) - $var(sl,left)) / double($var(RSlev))}]
		}
	}
	return $out
}

# namespace ::mon
proc getXcvrData {} {
	variable var

	## load current xcvr data
	set xcvrvar [namespace current]::var(rf12b)
	set $xcvrvar [xcvrData]
	## loop through all command words
	set var(disableTraces) 1
	while {[set cmd [enumerateCmd]] ne {}} {
		lassign $cmd C dat
		## only do control variables that start with a capital letter
		if {![string match "\[A-Z]*" $C] && $C ne "rfMon"} continue
		## loop through command field variables
		foreach f [dict keys $dat "\[A-Z]*"] {
			## initialize default values
			set var(xcvr,$C,$f) [dict get $dat $f def]
			## set traces so that dependent variables can be updated
			trace add variable var(xcvr,$C,$f) write [list [namespace current]::onTrace $xcvrvar]
		}
	}
	set var(disableTraces) 0
}

# namespace ::mon
proc init {{scanwidth 423}} {
	variable var

	# for debuging
	catch {
		close $var(port)
	}
	catch {
		unset var
	}
	array set var {
		title "RfMon"
		version v0.5

		B1 {}
		selecting 0

		scan,start 0

		top,margin 30
		left,margin 70
		bottom,margin 25
		mark,margin 160
		sl,left 0

		xmitting "Transmit"
		txtype CW
		txpower 0
		txdur 10
		txfreq 868.0
		xcvr {}
		xcvr,band 2
		mP {}
		xcvr,data {l 0 u 0 z 9 c 0 p 0}

		sx 0
		sy 0

		hold 0
		r 0
		state 0
		contimeout 1500
		markcnt 0
		maxrssi 1
		maxrssis {1}
		rssis {}
		portname ""
		port {}
		ports {}
		scale 9
		scandata {}
		scanbtn Scan

		history {}
		history,idx 0
		history,size 50
		con,inputLine 0

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
		marklines,on 1
		con,on 1
		sl,on 2
		bw,on 1
		sendi,on 1
		after,sendi {}
		
		lch 96
		uch 3903
		lbw 0
		ubw 0
		Pmin -103
		RSr 46
		RSstep 6
		RSresp 500
		RSlev 8
		portspeeds {
			9600
			14400
			19200
			28800

			38400
			56000
			57600
			76800
			111112
			115200
			128000
			230400
			250000
			256000
		}
		portspeed 57600
	}
	set var(scan,W) $scanwidth
	array set var [createDimensions $var(scan,W)]
	# calculate dBs per pixel
	array set var [list sa,top $var(wf,H) wf,top 0 sl,start [expr {$var(wf,W) + $var(sl,left)}] scan,end $var(scan,W) right,margin [expr {$var(wf,W) + 5}]]
	initFreqArray
	getXcvrData
	# set default values
	set var(xcvr,data) {b 2 l 96 u 3903 z 9 c 1600 p 0}
	set var(ports) [enumerate Ports]
	set var(gui) 1
	## turn off register update until application initializes
	set tmp $var(sendi,on)
	set var(sendi,on) 0
	buildTop
	set var(sendi,on) $tmp
	con "RfMon $var(version)\n(C) 2013,D.Zachariadis\nLicensed under GPLv3" 1
}

# namespace ::mon
proc initFreqArray {} {
	variable var
	# initialize frequency point array
	for {set i 0} {$i < $var(wf,W)} {incr i} {
		set var(fp,$i) 0
	}
	# initalize signal array
	for {set i 0} {$i <= $var(wf,H)} {incr i} {
		set var(sig,$i) 0
	}
	array unset var clock,*
	array unset var maxrssi,*

	set var(clock,0) [clock milli]
	array set var [list clock0 $var(clock,0) r 0 lbw 0 ubw 0]
	array set var [list sa,dBppx [expr {($var(sa,base) - $var(sa,top) - 15) / double($var(RSr))}] sl,end [expr {$var(wf,W) + $var(sa,H) + $var(sl,left)}]]
	array set var [list sa,RSpxps [expr {$var(RSstep) * $var(sa,dBppx)}] RSlev [expr {int($var(RSr) / double($var(RSstep)))}] mark,start [expr {$var(sl,end) + 3}]]
}

# namespace ::mon
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

# namespace ::mon
proc makeCtlWord {avar ctl {hex {}}} {
	variable var
	upvar $avar data

	set fields [dict get $data cmds $ctl]
	set cmdw [scan [dict get $fields cmd] %x]
	foreach f $fields {
		if {![info exists var(xcvr,$ctl,$f)] || ! [dict exists $fields $f lsb]} continue
		switch -glob -- [dict get $fields $f type] {
			cho* {
				set bits [dict get $fields $f opts $var(xcvr,$ctl,$f)]
			}
			func* {
				continue
			}
			default {
				set bits $var(xcvr,$ctl,$f)
			}
		}
		set shift [dict get $fields $f lsb]
		set cmdw [expr {$cmdw | ($bits << $shift)}]
	}
	if {$hex eq "hex"} {
		return 0x[format %04X $cmdw]
	}
	return $cmdw
}

# namespace ::mon
proc mark {e args} {
	variable var

	# canvas x,y
	lassign $args x y
	set W $var(scr)
	switch -glob -nocase -- $e {
		"FMark" {
			# no row info for a frequency mark
			cursor2event xc [list M F M$var(markcnt)]
			incr var(markcnt)
		}
		"TMark" {
			cursor2event tc [list M T Mt M$var(markcnt) r$y Et]
			incr var(markcnt)
		}
		"Event" {
			cursor2event xc [list M E M$var(markcnt) r$y]
			cursor2event tc [list M E M$var(markcnt) r$y Et]
			$var(scr) create oval [expr {$x - 5}] [expr {$y - 5}] [expr {$x + 5}] [expr {$y + 5}] -tags [list M E Mo M$var(markcnt) r$y] -outline #f60
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

# namespace ::mon
proc monSync {{data {}}} {
	variable var

	set var(xcvr,data) [dict merge $var(xcvr,data) $data]
	set var(xcvr,band) [dict get $var(xcvr,data) b]
	set var(xcvr,data) [dict merge $var(xcvr,data) [dict get $var(rf12b) bands $var(xcvr,band)]]
	set var(txfreq) [chan2freq [dict get $var(xcvr,data) c]]
	set var(scale) [dict get $var(xcvr,data) z]
	$var(scr) delete M
	drawGrid $var(scr)
}

# namespace ::mon
proc moveCursors {W x y} {
	variable var

	# when to hide vertical cursor
	if {0 > $x || $x > $var(sl,end)} {
		# cursor outside the frequency band
		$W itemconfig cross -state hidden
		$W configure -cursor {}
		$W itemconfig xc -state hidden
		# hide cross
		set cc 0
	} else {
		# where to draw vertical cursor
		showXcursor $W $x $y
		# show cross
		set cc 1
	}
	# when to hide horizontal cursor
	if {0 > $y || $y > $var(sa,base)} {
		# hide time cursor
		$W itemconfig tc -state hidden
		$W itemconfig cross -state hidden
		set cc 0
	} else {
		# where to draw horizontal cursor
		# showing cross cursor is determined by x
		showYcursor $W $x $y
	}
	updateCursors $x $y
	# whether to show the cross cursor
	if {$cc} {
		showCross $W $x $y
	} else {
		showCross $W {}
	}
}

# namespace ::mon
proc onChange args {
	variable var

	lassign $args what C field
	switch -glob -- $what {
		"port" {
			if {$C eq "conn"} {
				# indicate port connected
				$var(port,wg) configure -style green.TCombobox
				con "Connected" 1
				set var(state) 2
				set var(scanning) 1
				toggleScan			
			} elseif {$C eq "noId"} {
				# indicate failure to get xcvr id
				$var(port,wg) configure -style red.TCombobox
				con "No hardware id" 1
				set var(scanning) 0
				set var(state) 1
				toggleScan			
				return
			} elseif {$C eq "disc"} {
				$var(port,wg) configure -style {}
				con "Disconnected" 1
				set var(scanning) 0
				set var(state) 0
				toggleScan			
				return
			}
			if {$var(portname) eq "" || ! $var(evepch,on)} return
			set txt "[file tail $var(portname)]"
		}
		"set*" {
			set txt "$field=$var(xcvr,$C,$field) [dict get $var(rf12b) cmds $C $field units]"
		}
	}
	drawMark $txt -tag 1 -tags {M P Mt M$var(markcnt) Et}
}

# namespace ::mon
proc onConKey {key s} {
	variable var
#puts "$key"
	switch -glob -- $key {
		"Ret*" - "KP_Ent*" {
			set in [string trim [string range [$var(con) get $var(con,inputLine).0 [$var(con) index insert]] 2 end]]
			if {[info complete $in]} {
				set var(con,inputLine) [expr {int([$var(con) index end])}]
				# if not empty and not the same as previous command, append it to history
				if {[string length $in] > 0 && $in ne [lindex $var(history) end]} {
					lappend var(history) $in
					set var(history) [lrange $var(history) end-$var(history,size) end]
				}
				parseConCmd $in
				set var(history,idx) [llength $var(history)]
				return -code break
			}
		}
		"Back*" {
			if {[$var(con) comp insert <= $var(con,inputLine).0+2c]} {
				return -code break
			}
		}
		"Up" {
			if {[$var(con) comp insert < $var(con,inputLine).0]} {
				return
			}
			$var(con) delete $var(con,inputLine).2 end-1c
			if {$var(history,idx) >= 0} {
				incr var(history,idx) -1
				$var(con) insert end-1l+2c [lindex $var(history) $var(history,idx)]
			}
			$var(con) see end
			return -code break
		}
		"Down" {
			if {[$var(con) comp insert < $var(con,inputLine).0]} {
				return
			}
			$var(con) delete $var(con,inputLine).2 end-1c
			if {$var(history,idx) < [llength $var(history)]} {
				incr var(history,idx)
				$var(con) insert end-1c [lindex $var(history) $var(history,idx)]
			}
			$var(con) see end
			return -code break
		}
		"l" - "L" {
			# with COntrol key pressed, clear screen
			if {$s == 20} {
				$var(con) delete 0.0 end
				prompt
			}
		}
	}
}

# namespace ::mon
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
			if {$var(selecting) && $var(B1,dragging) ne {}} {
				lassign $var(B1,dragging) x0 y0
				set x [expr {$x < 0 ? 0 : $x > $var(wf,W) ? $var(wf,W) : $x}]
				$W coords BZ $x0 0 $x $var(sa,base)
			}
			moveCursors $W $x $y
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
				editMark "edit"
			} elseif {$var(selecting) || ($s & 0x11) == 0x11} {
				set var(selecting) 1
				# draw band
				$var(scr) delete BZ
				set x [expr {$x < 0 ? 0 : $x > $var(wf,W) ? $var(wf,W) : $x}]
				set var(B1,dragging) [list $x $y $s]
				$var(scr) create rect $x 0 $x $var(wf,H) -stipple gray12 -fill #400 -outline #800 -tags {BZ}
			} else {
				## tune here
				tuneHere $x
			}
		}
		"B3" {
			set var(B1) {}
			$W itemconfig EE -state hidden -tags EE
			set tags [inside? $x $y]
			set var(popup,xy) [list $x $y $tags]
			tk_popup $var(popup) $X $Y
		}
		"B1R" {
			set x [expr {$x < 0 ? 0 : $x > $var(wf,W) ? $var(wf,W) : $x}]
			if {$var(selecting)} {
				zoneSelect end [lindex $var(B1,dragging) 0] $x
				$W del BZ
			}
			set var(B1,dragging) {}
		}
		"wheel" {
			#puts $args
		}
		default {
			#puts default\t$e\t$args
		}
	}
}

# namespace ::mon
proc onPanelEvent args {
	variable var

	lassign $args W tgt what x y s d
	switch -glob -nocase -- $what {
		"whe*" {
			$tgt yview scroll [expr {$d < 0 ? 20 : -20}] u
		}
		"B1" {
			set tags [$tgt gettags [$tgt find withtag $d]]
			set var(pan,B1) [list $x $y $s $tags]
			set var(pan,B1M) {}
			$tgt raise [lindex $tags 1]
		}
		"B1M" {
			lassign $var(pan,B1) x0 y0
			$tgt move [lindex $var(pan,B1) end 1] [expr {$x-$x0}] [expr {$y-$y0}]
			# TODO maybe put something more useful here
			set var(pan,B1M) $var(pan,B1)
		}
		"B1R" {
			set var(pan,B1) {}
			$tgt config -scrollregion [$tgt bbox all]
			if {$var(pan,B1M) ne {}} {
				set var(pan,B1M) {}
				# prevent other actions if the widget moved
				return -code break
			}
			set var(pan,B1M) {}
		}
		default {
			puts [$tgt gettags all]
		}
	}
}

# namespace ::mon
proc onTrace args {
	## calculates human understandable values for control fields
	variable var
	# this is a trace callback, but if traces are not required, then do nothing
	if {$var(disableTraces)} return
	# avoid triggering a race condition with traces by disabling them
	set var(disableTraces) 1
	# recover xcvr data
	lassign $args datavar avar item
	upvar $datavar data
	set controls [dict get $data cmds]
	# item is the variable that changed and got us here
	lassign [split $item ,] i cmd field

	switch -glob -- $cmd,$field {
		FSC,F - CSC,FB {
			# set frequency from the channel field
			set band [dict get $controls CSC FB opts $var(xcvr,CSC,FB)]
			set var(xcvr,FSC,Freq) [format %0.4f [chan2freq $var(xcvr,FSC,F) $band]]
		}
		FSC,Freq {
			## set channel and band
			lassign [freq2chband $var(xcvr,FSC,Freq)] var(xcvr,CSC,FB) var(xcvr,FSC,F) b
			set var(xcvr,band) $b
			if {[dict exists $controls FSC Freq format]} {
				set var(xcvr,FSC,Freq) [format [dict get $controls FSC Freq format] $var(xcvr,FSC,Freq)]
			}
		}
		DRC,Cs - DRC,R {
			## change BR
			set var(xcvr,DRC,BR) [format %0.3f [expr {10000 / 29.0 / ($var(xcvr,DRC,R) + 1) / (1 + $var(xcvr,DRC,Cs) * 7)}]]
			## change DBR
			set var(xcvr,DRC,DBR) 0
		}
		DRC,BR {
			# data rate in kbps
			set var(xcvr,DRC,R) [expr {round(10000 / 29.0 / (1 + $var(xcvr,DRC,Cs) * 7) / $var(xcvr,DRC,BR)) - 1}]
			set var(xcvr,DRC,DBR) [format %0.3f [expr {$var(xcvr,DRC,BR) - (10000 / 29.0 / ($var(xcvr,DRC,R) + 1) / (1 + $var(xcvr,DRC,Cs) * 7))}]]
		}
		WUT,M - WUT,R {
			set var(xcvr,WUT,Twu) [format %0.1f [expr {1.03 * $var(xcvr,WUT,M) * pow(2,$var(xcvr,WUT,R)) + 0.5}]]
			set var(xcvr,LDC,Dc) [format %0.1f [expr {$var(xcvr,WUT,M) ? ($var(xcvr,LDC,Dcs) * 2.0 + 1.0) / double($var(xcvr,WUT,M)) * 100.0 : Inf}]]
		}
		LDC,Dcs {
			set var(xcvr,LDC,Dc) [format %0.1f [expr {$var(xcvr,WUT,M) ? ($var(xcvr,LDC,Dcs) * 2.0 + 1.0) / double($var(xcvr,WUT,M)) * 100.0 : Inf}]]
		}
		LBD,V {
			set var(xcvr,LBD,Vlb) [format %0.2f [expr {2.25 + $var(xcvr,LBD,V) * 0.1}]]
		}
	}
	set var(xcvr,$cmd) [makeCtlWord $datavar $cmd hex]
	# should we send the change immediatelly to the xcvr?
	if {$var(sendi,on)} {
		after cancel $var(after,sendi)
		set var(after,sendi) [after 500 "
			[namespace current]::send \[scan \$[namespace current]::var(xcvr,$cmd) %x]r
		"]
	}
	if {$var(gui)} {
		event generate $var(scr) <<ValueChange>> -data $cmd,$field
	}
	set var(disableTraces) 0
}

# namespace ::mon
proc onValueChange cmd {
	variable var

	switch -nocase -glob -- $cmd {
		"RCC,BW" -
		"FSC,Freq" -
		"FSC,F" {
			drawRxBW $var(scr)
		}
		"CSC,FB" {
			monSync [list b [dict get $var(rf12b) cmds CSC FB opts $var(xcvr,CSC,FB)]]
			drawRxBW $var(scr)
		}
	}
}

# namespace ::mon
proc opts2dict {W tag} {
	set opts {}
	foreach o [$W itemconfig $tag] {
		lassign $o opt _ _ _ val
		lappend opts $opt $val
	}
	return $opts
}

# namespace ::mon
proc parseConCmd line {
	if {[llength $line]} {
		send $line
	} else {
		prompt
	}
}

# namespace ::mon
proc plotSignal data {
	variable var
	set coords {}
	for {set y 0} {$y < $var(wf,H)} {incr y} {
		lappend coords [expr {[lindex $data $y] + $var(sl,start)}] $y
	}
	if {$coords eq {}} return
	$var(scr) coords SL $coords
}

# namespace ::mon
proc portError err {

	if {[regexp -- {couldn't open "(.*)"} $err _ port] && [string trim $port] eq ""} {
		set msg "No port defined"
	} else {
		set msg "Not connected."
	}
	tk_messageBox -message $msg -detail "Please select a port\nconnected to the receiver" -icon info
}

# namespace ::mon
proc portSetup {} {
	variable var

	catch {
		close $var(port)
	}
	set var(port) {}
	if {$var(gui)} {
		event generate $var(top) <<PortChanged>> -data disc
	}
	if {[string match "disc*" $var(portname)] || ![llength $var(portname)]} {
		set var(portname) {}
		return
	}
	if {[catch {
		set var(port) [open $var(portname) RDWR]
	} err]} {
		set var(scanning) 0
		# skip toggleScan resume
		return -level 2
	}
	set var(state) 1
	# empty input buffer
	chan config $var(port) -blocking 0 -buffering line -mode $var(portspeed),n,8,1
	read $var(port)
	chan event $var(port) read [list [namespace current]::receive $var(port)]
	send "v9zs\n"
	set var(concnt) 4
	set var(afteropen) [after $var(contimeout) [namespace current]::xcvrGetId]
	con "Opended $var(portname)\n"
}

# namespace ::mon
proc print {} {
	variable var
	dict for {C fields} [dict get $var(rf12b) cmds] {
		if {![string match "\[A-Z]*" $C] || ![info exists var(xcvr,$C)]} continue
		lappend out $var(xcvr,$C) [dict get $fields desc]
	}
	foreach {C desc} [lsort -stride 2 -dict -index 1 $out] {
		con $C\t$desc\n
	}
	con "" 1
}

# namespace ::mon
proc prompt {} {
	variable var

	$var(con) mark set insert end-1c
	$var(con) insert end "\n% "
	set var(con,inputLine) [expr {int([$var(con) index end-1c])}]
	$var(con) see end
}

# namespace ::mon
proc quit {} {
	variable var
	catch {
		chan close $var(port)
	}
	exit
}

# namespace ::mon
proc receive port {
	variable var

	if {![gets $port var(scandata)] || ![string length $var(scandata)]} {
		return
	}
	xcvrParseResp
}

# namespace ::mon
proc rgb {colors {r {0 0 255 255}} {g {0 0 255 255}} {b {0 0 255 255}}} {
	set i 0
	foreach R [colors $colors {*}$r] G [colors $colors {*}$g] B [colors $colors {*}$b] {
		lappend palette $i [format #%02x%02x%02x $R $G $B]
		incr i
	}
	return $palette
}

# namespace ::mon
proc savePrefs {} {
}

# namespace ::mon
proc scanSync {{data {}}} {
	variable var

	# find where on screen should the scan start and end
	set var(scan,start) [expr {([dict get $var(xcvr,data) l] - $var(lch)) / [dict get $var(xcvr,data) z]}]
	set var(scan,end) [expr {([dict get $var(xcvr,data) u] - $var(lch)) / [dict get $var(xcvr,data) z]}]
	set var(state) 3
	set var(hold) 0
	$var(scr) delete info
}

# namespace ::mon
proc scr2chan x {
	variable var

	expr {[dict get $var(rf12b) lch] + $x * $var(scale)}
}

# namespace ::mon
proc scr2freq x {
	variable var

	chan2freq [scr2chan $x]
}

# namespace ::mon
proc send s {
	variable var

	if {[catch {
		puts $var(port) $s
		con $s
	} err] && $var(scanning)} {
		con $err 1
	}
}

# namespace ::mon
proc Set args {
	# send control register to the xcvr
	# args is {command field}
	variable var

	lassign $args C fie
	set fields [dict get $var(rf12b) cmds $C]
	set cmdw [scan [dict get $var(rf12b) cmds $C cmd] %x]

#	switch -glob -- [dict get 
 	foreach f $fields {
		if {![info exists var(xcvr,$C,$f)]} continue
		set bits [scan [dict get $fields $f opts $var(xcvr,$C,$f)] %b]
		set shift [dict get $fields $f lsb]
		set cmdw [expr {$cmdw | ($bits << $shift)}]
	}
	if {[info command [namespace current]::_set[lindex $args end]] ne {}} {
		[namespace current]::_set[lindex $args end] {*}$args 
	}
	set var(xcvr,last,cmdw) 0x[format %x $cmdw]
	send ${cmdw}r
	event generate $var(top) <<SettingsChanged>> -data [list setting $C $fie]
}

# namespace ::mon
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

# namespace ::mon
proc showCross {W x {y {}}} {
	variable var

	if {$x ne "" && ($y <= $var(wf,H) || $x <= $var(wf,W))} {
		$W coords cross $x $y
		$W itemconfig cross -state normal
		$W config -cursor none
	} else {
		$W itemconfig cross -state hidden
		$W config -cursor {}
	}
}

# namespace ::mon
proc showXcursor {W x y} {
	variable var

	if {$y >=0} {
		set ty [expr {-11 - 9 * ($var(markcnt) %2)}]
		set tx [expr {$x + 6}]
		$W coords xca $tx $ty $x $ty $x 0
		$W coords xct $tx $ty
		# show freq or dBm ?
		if {$x <= $var(wf,W)} {
			# freq
			$W itemconfig xct -text [format " %0.2f" [scr2freq $x]]
			$W coords xcl $x 0 $x $var(sa,base)
		} else {
			# dBm
			$W itemconfig xct -text [format " %0.1f" [expr {[dict get $var(rf12b) Pmin] - $var(RSstep) + ($x - $var(wf,W) - $var(sl,left)) / $var(sa,dBppx)}]]
			$W coords xcl $x 0 $x $var(wf,H)
		}
		$W itemconfig [list xca || xct] -state normal
	} else {
		$W itemconfig [list xca || xct] -state hidden
	}
	$W itemconfig xcl -state normal
}

# namespace ::mon
proc showYcursor {W x y} {
	variable var

	if {$y <= $var(wf,H)} {
		# show time cursor
		$W coords tcl 0 $y $var(sl,end) $y
		$W coords tct -12 $y
		$W coords tca -10 $y 0 $y
		if {[info exists var(clock,$y)]} {
			$W itemconfig tct -text "[clock format [expr {$var(clock,$y)/1000}] -format %H:%M:%S][string range [expr {fmod($var(clock,$y)/1000.0,1)}] 1 3]"
		} else {
			$W itemconfig tct -text "No data"
		}
	} else {
		# show dBm
		$W coords tcl 0 $y $var(wf,W) $y
		$W coords tct -30 $y
		$W coords tca -28 $y 0 $y
		$W itemconfig tct -text [format %0.1f [expr {($var(sa,base) - $y) / $var(sa,dBppx) + [dict get $var(rf12b) Pmin] - $var(RSstep)}]]
	}
	$W itemconfig tc -state normal
	$W itemconfig tc -state normal
}

# namespace ::mon
proc test {} {
	set out {}
	set i 0
	dict for {k v} [dict get $mon::var(rf12b) cmds] {
		if {![dict exists $v cmd]} continue
		lappend out [dict get $v desc] [dict get $v cmd] $k
	}
	set out [lsort -dict -stride 3 $out]
	foreach {k v c} $out {
		puts "\tword $c;\t// \[$i] $k"
		incr i
	}
}

# namespace ::mon
proc toggleScan {} {
	variable var

	if {$var(state) < 2} {
		$var(scanb) configure -text "Scan"
		return
	}
	if {$var(scanning)} {
		send "s"
		$var(scanb) configure -text "Stop"
	} else {
		send "z"
		$var(scanb) configure -text "Scan"
	}
}

# namespace ::mon
proc tuneHere f {
	## tune on this point on screen
	variable var
	
	# use current bandwidth value
	set var(xcvr,FSC,F) [scr2chan $f]
	set var(xcvr,FSC,Freq) [scr2freq $f]
	set var(lbw) [freq2scr [expr {$var(xcvr,FSC,Freq) - $var(xcvr,RCC,BW) / 2000.0}]]
	set var(ubw) [freq2scr [expr {$var(xcvr,FSC,Freq) + $var(xcvr,RCC,BW) / 2000.0}]]
	if {$var(gui)} {
		event generate $var(scr) <<ValueChange>> -data FSC,Freq
	}
}

# namespace ::mon
proc updateCursors {x y} {
	variable var

	$var(scr) itemconfig clock -text [clock format [expr {$var(clock,$var(r))/1000}] -format %H:%M:%S][string range [expr {fmod($var(clock,$var(r))/1000.0,1)}] 1 2]

	if {$var(sl,on) > 1} {
		plotSignal [getSignalLine $x]
	}
	if {$var(scan,start) > $x || $x >= $var(scan,end)} return
	
	set rssi 0
	# move horizontal cursor in spectrum analyzer
	set xi [expr {$x - $var(scan,start)}]
	if {$var(avgs,on)} {

		if {[info exists var(fp,$xi)]} {
			set rssi $var(fp,$xi)
		} else {
			set rssi 0
		}
	} else {
		set rssi [lindex $var(scandata) $xi]
		if {$rssi eq ""} {
			set rssi 0
		}
	}
	set yrssi [expr {$var(sa,base) - $var(RSstep) * $var(sa,dBppx) * $rssi}]
	$var(scr) coords ycat -30 $yrssi
	$var(scr) itemconfig ycat -text "[format %0.1f [expr {$var(Pmin) + $var(RSstep) * ($rssi - 1)}]]"
	$var(scr) coords ycal 0 $yrssi $x $yrssi
	if {$var(sl,on) == 1} {
		plotSignal [getSignalLine $x]
	}
}

# namespace ::mon
proc validateScalar s {
	string is double -strict $s
}

# namespace ::mon
proc xcvrData {} {
	# TODO better impleent the xcvr as an object 1600
	variable var

	return {
		bands {
			1 {c1 1 c2 43 PLLstep 2.5 Pmax 7 name 433}
			2 {c1 2 c2 43 PLLstep 5.0 Pmax 5 name 868}
			3 {c1 3 c2 30 PLLstep 7.5 Pmax 5 name 915}
		}
		lch 96 uch 3903 Pmin -103 RSr 46 RSstep 6 RSresp 500 RSlev 8
		portspeed 57600
		txpower {0 0 -2.5 1 -5.0 2 -7.5 3 -10.0 4 -12.5 5 -15.0 0 -17.5 7}
		cmds {
			FSC {
				desc {3. Frequency Setting}
					cmd 0xA000 
					F {desc {Channel} lsb 0 type scalar from 96 to 3903 incr 1 units {} def 1600}
					Freq {desc Frequency type entry from 0.0 to 1000.0 incr 0.25 units MHz def 868.00000 format %0.4f deps {FSC,F CSC,FB}}
			}
			CSC {
				desc {1. Configuration Setting}
				cmd 0x8000 
				FB {desc {Freq. Band} lsb 4 type choice opts {915 3 868 2 433 1} units MHz def 868}
				El {desc {TX register enable} type boolean lsb 7 def 0 units {}}
				Ef {desc {RX FIFO enable} type boolean lsb 6 def 0 units {}}
				CLC {desc {Xtal load capac.} lsb 0 type choice opts {8.5 0 9 1 9.5 2 10 3 10.5 4 11 5 11.5 6 12 7 12.5 8 13.0 9 13.5 10 14 11 14.5 12 15 13 15.5 14 16 15} units {pF} def 12}
			}
			RCC {
				desc {5. Receiver Control}
				cmd 0x9000 
				Pin16 {desc {Pin16} lsb 10 type choice opts {{Interrupt input} 0 {VDI output} 1} units {} def {VDI output}}
				VDI {desc {VDI timing} lsb 8 type choice opts {Fast 0 Medium 1 Slow 2 {Always on} 3} units {} def Fast}
				BW {desc {RX Bandwidth} lsb 5 type choice opts {400 1 340 2 270 3 200 4 134 5 67 6}	units kHz def 67 deps {}}
				LNA {desc {LNA gain}	lsb 3 type choice opts {0 0 -6 1 -14 2 -20 3} units dB def 0}
				RSSI {desc {RSSI threshold}	lsb 0 type choice opts {-61 7 -67 6 -73 5 -79 4 -85 3 -91 2 -97 1 -103 0} units dB def -103}
			}
			DRC {
				desc {4. Data Rate}
				cmd 0xC600 
				R {desc {Rate setting (R)} lsb 0 type scalar from 0 to 127 incr 1 units {} def 35 format %0.0f width 4 deps {DRC,BR DRC,Cs}}
				Cs {desc {Prescaler ÷8 (Cs)} lsb 7 type boolean opts {0 1} units {} def 0 }
				BR {desc {Bit Rate (BR)} type entry from 0.337 to 344.827 incr 1.0 incr 0.5 units kbps def 9.5790 format %0.3f  deps {DRC,R DRC,Cs}}
				DBR {desc {ΔBR} deps {} type function from 0.0 to 100.0 format %0.3f units kbps def 0 format %0.3f}
			}
			TXC {
				desc {11. Transmitter Config.}
				cmd 0x9800
				Mp {desc {Freq. Shift} lsb 8 type choice opts {Positive 0 Negative 1} units {} def Positive }
				M {desc {FSK shift} lsb 4 type choice opts {240	15 225	14 210	13 195	12 180	11 165	10 150	9 135	8 120	7 105	6 90	5 75	4 60	3 45	2 30	1 15	0 } units {kHz} def 15}
				Pwr {desc {Power output} lsb 0 type choice opts {0.0	0 -2.5	1 -5.0	2 -7.5	3 -10.0	4 -12.5	5 -15.0	6 -17.5	7} units {dB} def 0.0}
			}
			PMC {
				desc {2. Power Management}
				cmd 0x8200 
				Er {desc {RX enable} lsb 7 type boolean units {} def 0 }
				Ebb {desc {RX baseband} lsb 6 type boolean units {} def 0 }
				Et {desc {TX enable} lsb 5 type boolean units {} def 0 }
				Es {desc {Synthesizer} lsb 4 type boolean units {} def 0 }
				Ex {desc {Xtal oscillator} lsb 3 type boolean units {} def 1 }
				Eb {desc {Low bat. detect.} lsb 2 type boolean units {} def 0 }
				Ew {desc {Wake-up timer} lsb 1 type boolean units {} def 0 }
				Dc {desc {Disable clock output} lsb 0 type boolean units {} def 0 }
			}
			DFC {
				desc {6. Data Filter}
				cmd 0xC228 
				Al {desc {Data recovery} lsb 7 type choice opts {auto 1 manual 0} units {} def manual}
				Ml {desc {Recovery speed} lsb 6 type choice opts {fast 1 slow 0} units {} def slow}
				S {desc {Filter type} lsb 4 type choice opts {digital 0 {analog RC} 1} units {} def digital}
				DQD {desc {Data quality thresh.} lsb 0 type scalar from 0 to 7 incr 1 units {} def 4}
			}
			FIFO {
				desc {7. FIFO & Reset Mode}
				cmd 0xCA00 
				IT {desc {FIFO INT level} lsb 4 type scalar from 0 to 15 incr 1 units {} def 8}
				Sp {desc {Synchron length} lsb 3 type choice opts {1 0 2 1} units byte def 1}
				Al {desc {FIFO fill start} lsb 2 type choice opts {{Sync pattern} 0 {Always fill} 1} units {} def {Sync pattern}}
				Ff {desc {FIFO fill enable} lsb 1 type boolean units {} def 0}
				Dr {desc {RESET sens.} lsb 0 type choice opts {High 0 Low 1} units {} def High}
			}
			SP {
				desc {8. Synchron Pattern}
				cmd 0xCE00 
				B {desc {Byte0/Group} lsb 0 type entry from 0 to 255 incr 1 units {} def 212}
			}
			AFC {
				desc {10. AFC}
				cmd 0xC400
				A {desc {Auto AFC} lsb 6 type choice opts {Off 0 {Once} 1 {While VDI high} 2 {On} 3} units {} def On}
				Rl {desc {Offset limit} lsb 4 type choice opts {{No limit} 0 {-16..+15} 1 {-8..+7} 2 {-4..+3} 3} units {chan} def {-4..+3}}
				St {desc {Strobe edge} lsb 3 type boolean units {} def 0 }
				Fi {desc {Fine mode} lsb 2 type boolean units {} def 1 }
				Oe {desc {Freq. offset enable} lsb 1 type boolean units {} def 1 }
				En {desc {Offset calc. enable} lsb 0 type boolean units {} def 1 }
			}
			PLL {
				desc {12. PLL Setting}
				cmd 0xCC12
				Ob {desc {Clock output for} lsb 5 type choice opts {{5-10} 3 {3.3} 2 {<=2.5} 0} units {MHz} def {5-10}}
				Dly {desc {Phase det. delay} lsb 3 type boolean units {} def 1 }
				Ddit {desc {Disable dithering} lsb 2 type boolean units {} def 1 }
				Bw0 {desc {PLL band} lsb 0 type choice opts {86.2 0 256 1} units {kbps} def 86.2}
			}
			TRW {
				desc {13. Xmitter Reg. Write}
				cmd 0xB800
				Dat {desc {Data} lsb 0 type entry from 0 to 255 incr 1 units {} def 170}
			}
			WUT {
				desc {14. Wake-Up Timer}
				cmd 0xE000
				R {desc {Exponent} lsb 8 type entry from 0 to 31 incr 1 units {} def 1}
				M {desc {Mantisa} lsb 0 type entry from 0 to 255 incr 1 units {} def 150}
				Twu {desc {Wake-up time} type function units {ms} def 155 deps {WUT,R WUT,M}}
			}
			LDC {
				desc {15. Low Duty-Cycle}
				cmd 0xC800
				En {desc {Low duty-cycle} lsb 0 type boolean units {} def 0 }
				Dcs {desc {Setting} lsb 1 type scalar from 0 to 127 incr 1 units {} def 7}
				Dc {desc {Duty-cycle} type function units {%} def 10.0 deps {LDC,Dcs WUT,M}}
			}
			LBD {
				desc {16. Low Bat.& clk divider}
				cmd 0xC000
				V {desc {Low bat. setting} lsb 0 type scalar from 0 to 15 incr 1 units {} def 0}
				Vlb {desc {Low bat. thresh.} type function units {V} def 2.25 deps {LBD,V}}
				Cd {desc {Clock out freq.} lsb 5 type choice opts {1.0 0 1.25 1 1.66 2 2.0 3 2.5 4 3.33 5 5.0 6 10.0 7} units {MHz} def 1.0}
			}
			RFR {
				desc {9.Receiver FIFO read}
				cmd 0xB000 
			}
			SR {
				desc {17. Status Read}
				cmd 0x0000
			}
			rfMon {
				desc RfMon
				cmd 0
				desc {RfMon combos}
				Id {desc {Node ID} type entry from 1 to 31 incr 1 width 3 units {} def 1 state disabled}
				Ack {desc {Request ACK} type boolean units {} def 0 state disabled}
				Zw {desc {Scan width} type entry from 1 to 3808 incr 1 units {chan} def 3808 state disabled}
			}
		}
	}
}

# namespace ::mon
proc xcvrGetId {} {
	variable var
	incr var(concnt) -1
	if {$var(concnt)} {
		send "v9zs\n"
		set var(afteropen) [after $var(contimeout) [namespace current]::xcvrGetId]
	} else {
		set var(hw) {}
		event generate $var(top) <<PortChanged>> -data noId
	}
}

# namespace ::mon
proc xcvrParseResp {} {
	variable var

	if {[string index $var(scandata) 0] eq "<"} {
		set var(state) 1
#puts parseScandata\t$var(scandata)
		con \n$var(scandata) 1
		switch -glob -- [lindex $var(scandata) 0] {
			"*s" {
				# sync with receiver's settings
				scanSync $var(scandata)
			}
			"*v" {
				# firmware signatiure
				set var(state) 2
				after cancel $var(afteropen)
				set var(xcvr,data) [dict merge $var(xcvr,data) [lrange $var(scandata) 1 end]]
				monSync
				set var(hw) [dict get $var(xcvr,data) hw]
				wm title $var(top) "$var(title) - [dict get $var(xcvr,data) xcvr] $var(hw)"
				event generate $var(top) <<PortChanged>> -data conn
			}
			"*x" {
				set var(xmitting) "Transmit"
			}
			default {
				if {[llength $var(scandata)] > 2} {
					set var(xcvr,data) [dict merge $var(xcvr,data) [lrange $var(scandata) 1 end]]
					monSync
					scanSync
					return
				}
			}
		}
		return
	} elseif {[string length $var(scandata)] > 0} {
		if {$var(r) < $var(wf,H)} {
			incr var(r)
		} else {
			set var(r) 0
		}
		set var(clock,$var(r)) [clock milli]
		set var(scandata) [split $var(scandata) ""]
		drawScanline
	}
}

# namespace ::mon
proc xmit {{what {}}} {
	variable var

	switch -nocase -glob -- $what {

		"power" {
			send "[dict get $var(rf12b) txpower $var(txpower)]p"
		}
		"band" - "freq*" {
			set bands [dict keys [dict get $var(rf12b) bands]]
			set ch ""
			# user entered individual frequency
			# find and set the band this frequency is in
			foreach b $bands {
				if {[chan2freq [dict get $var(rf12b) lch] $b] <= $var(txfreq) && $var(txfreq) < [chan2freq [dict get $var(rf12b) uch] $b]} {
					set var(xcvr,band) $b
					set ch "[freq2chan $var(txfreq)]c"
					break
				}
			}
			if {![info exists ch]} {
				set var(xcvr,band) 2 ; # default
				set ch ""
			}
			send "$var(xcvr,band)b$ch"
		}
		"type" {
			# send the command to the xceiver
		}
		default {
			if {$var(xmitting) ne "Transmit" || $var(port) eq ""} {
				return
			}
			set pwr [dict get $var(rf12b) cmds TXC Pwr opts $var(xcvr,TXC,Pwr)]
			send "$var(txdur)x"
			set var(xmitting) "Transmitting..."
		}
	}
}

# namespace ::mon
proc zoneSelect {what args} {
	variable var
	if {$what eq "start"} {
		set var(selecting) 1
		set var(B1,dragging) {}
		return
	} elseif {$what eq "reset"} {
		send "$var(lch)l$var(uch)u$var(scale)zs"
		return
	}
	# end select
	set var(selecting) 0
	# s1, s2 are the screen x coords of the selection zone
	lassign $args s1 s2
	if {$s1 eq "" || $s2 eq ""} return

	set var(hold) 1
	# sort the screen coords in increasing order
	set tmp [expr {min($s1,$s2)}]; set s2 [expr {max($s1,$s2)}]; 	set s1 $tmp
	# find the frequencies corresponding to the zone limits
	set f1 [scr2freq $s1]
	set f2 [scr2freq $s2]
	# find the channels corresponding to the zone limits
	set scale [expr {double($s2 - $s1) / $var(wf,W)}]
	set lch [expr {$var(lch) + $s1 * $var(scale)}]
	set uch [expr {$var(lch) + $s2 * $var(scale)}]
	# limit scan line on screen
	set var(scan,start) $s1
	set var(scan,end) $s2
	# tell the transceiver the new scan limits
	send "${lch}l${uch}u$var(scale)zs"
	# warn the user for the change
	$var(scr) create text [expr {$var(wf,W) /2}] [expr {$var(wf,H)/2}] -text "Setting receiver.\nPlease wait..." -font {TkDefaultFont -14} -fill #fff -tags info
	# clear arrays
	initFreqArray
	# blanc screen
	$var(wfi) put #000 -to 0 0 $var(wf,W) $var(wf,H)
	# send an event for adjusting other parameters, like grid etc.
	if {$var(gui)} {
		event generate $var(scr) <<ValueChange>> -data FSC,Freq
	}
}
}; # end of namespace ::mon

proc ::main {} {
	::mon::init
}
##
main


