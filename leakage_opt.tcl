proc leakage_opt { uno arrivalTime due criticalPaths tre slackWin } {


	if { [ string compare $uno "-arrivalTime" ] != 0 || [ string compare $due "-criticalPaths"] != 0 \
		|| [ string compare $tre "-slackWin" ] != 0 } {
		puts "Syntax is: leakage_opt -arrivalTime X -criticalPaths Y -slackWin Z"
		return [list 0 0 0 0]
	}

	if { $arrivalTime <= 0 } {
		puts "Please specify an arrival time > 0."
		return [list 0 0 0 0]
	}

	if { [string first "." $criticalPaths] != -1 } {
		puts "Please specify an integer number of critical paths."
		return [list 0 0 0 0]
	}

	if { $slackWin <= 0 } {
		puts "Please specify a slack window size > 0."
		return [list 0 0 0 0]
	}
		

#	report_timing

	suppress_message NLE-019

	set start_time [clock clicks]

	set power_before [ total_leak_power ]

	#puts "Leakage power before optimization is $power_before nW"

	# verify that arrivalTime is already satisfied
	set worst_path_arrival [get_attribute [get_timing_paths] arrival]
	if { $worst_path_arrival > $arrivalTime } {
		puts "Unfeasible arrival time."
		return [list 0 0 0 0]
	}

	set clock_period [get_attribute [get_clock] period]
		if {[expr $arrivalTime > $clock_period]} {
			puts "The requested arrival time is greater than the synthesis clock period."
			puts "The slack window will be redefined."
			# Redefine the slack window
			set slackWin [expr [get_attribute [get_clock] period] - $arrivalTime + $slackWin]
			set zero [expr 0 - $arrivalTime + [get_attribute [get_clock] period]]
		} else {
			set zero 0
	}

	puts "The slack window goes from $zero to $slackWin."

	set paths_in_slackWin [sizeof_collection [get_timing_paths -slack_lesser_than $slackWin -max_paths 1000]]

	if { $paths_in_slackWin > $criticalPaths } {
		puts "Unfeasible number of critical paths ($paths_in_slackWin already in the slack window)."
		return [list 0 0 0 0]
	}

	# get the paths outside of slackWin
	set paths [get_timing_paths -slack_greater_than $slackWin -max_paths 1000]

	#puts "Found [sizeof_collection $paths] paths outside the slack window"

	if {[expr [sizeof_collection $paths] <= 0]} {
		puts "Found no paths to improve on. Quitting..."
		return [list 0 0 0 0]
	}
	
	foreach_in_collection path $paths {
		# for each 
		foreach_in_collection timing_point [get_attribute $path points] {
			# Get cell name of this timing point:
			set point_name [get_attribute [get_attribute $timing_point object] full_name]
			
			# Is this timing point an output?
			if { [expr [string first "U" $point_name] == 0] && [expr [ string first "/Z" $point_name ] > 0] } {
				#puts "Found output node $point_name;"
				# Get the name of the cell
				set cell_name [ lindex [ split $point_name "/" ] 0 ]
				# Have we already analyzed this cell?
				if {![info exists leakage_lvt($cell_name)]} {
					# Get the arrival time and leakage power for LVT
					set delay_lvt($cell_name) [ get_attribute [ get_timing_paths -through $point_name ] arrival ]
					#puts "Delay of $cell_name for LVT is $delay_lvt($cell_name) ns"
					set leakage_lvt($cell_name) [ leak_power $cell_name ]
					#puts "Leakage of $cell_name for LVT is $leakage_lvt($cell_name) nW"
				} else {
					#puts "$cell_name already analyzed, skipping..."
				}
			}
		}
	}

	#puts "----------------------------------------------------------------------"

	# Now get the HVT values
	foreach {key value} [array get leakage_lvt] {
		# Swap cell to HVT
		#puts "Swapping $key to HVT"
		cell_swapper $key HVT
		# Get values for HVT
		set delay_hvt($key) [ get_attribute [ get_timing_paths -through $key/Z ] arrival ]
		#puts "Delay of $key for HVT is $delay_hvt($key) ns"
		set leakage_hvt($key) [ leak_power $key ]
		#puts "Leakage of $key for HVT is $leakage_hvt($key) nW"
		# Swap back to LVT
		#puts "Swapping $key to LVT"
		cell_swapper $key LVT
	}

 	#parray leakage_lvt > leakage_lvt.txt
 	#parray delay_lvt > delay_lvt.txt
	
 	#parray leakage_hvt > leakage_hvt.txt
 	#parray delay_hvt > delay_hvt.txt


 	## calculate K of each cell

	foreach {key value} [array get leakage_hvt] {
		set delta_leak [expr $value - $leakage_lvt($key)]
		set delta_delay [expr $delay_hvt($key) - $delay_lvt($key)]
		set kappa_tmp [expr $delta_leak / $delta_delay]
		# array setup as key = K, value = cellname
		while {[info exists kappa($kappa_tmp)]} {
			#append 0 to $kappa_tmp
			if {[string first "." $kappa_tmp]} {
				append kappa_tmp "0"
			} else {
				# if kappa_tmp is an integer
				append kappa_tmp ".0"
			}
		}	
		set kappa($kappa_tmp) $key
		# also add K to a list for sorting
		set kappa_list [ lappend kappa_list $kappa_tmp ]
	}

# 	# sort by K

 	set kappa_list [lsort -real -increasing $kappa_list]

	# puts $kappa_list

 	# parray kappa > kappa.txt

	# get the length of kappa_list

	set base 0

	set length [llength $kappa_list]

	while { 1 } {

		set length [expr $length / 2]

		if {[expr $length <= 0]} {
			break
		}
	
		puts "Swapping from $base to [expr $base + $length - 1] to HVT"

		foreach kappa_tmp [lrange $kappa_list $base [expr $base + $length - 1]] {
			cell_swapper $kappa($kappa_tmp) HVT
		}

		set base [expr $base + $length]

		while { [ expr [get_attribute [get_timing_paths] slack] < $zero ] || \
			 [ expr [sizeof_collection [get_timing_paths \
				-slack_lesser_than $slackWin -max_paths 1000]] > $criticalPaths ] || \
			 [ expr [get_attribute [get_timing_paths] arrival] > $arrivalTime ] } {
			# if conditions are not met, swap everything back, and try with a subset
			if {$length > 1} {
				set length [expr $length / 2]
			}

			if {[expr $length <= 0]} {
				break
			}
			
			puts "Swapping from [expr $base - $length] to [expr $base - 1] to LVT"
			foreach kappa_tmp [lrange $kappa_list [expr $base - $length] [expr $base - 1]] {
				cell_swapper $kappa($kappa_tmp) LVT
			}

			set base [expr $base - $length]
		}
	}

	#puts "--- End of pass 1"

	#puts "Slack is [get_attribute [get_timing_paths] slack]"
	#puts "N. of paths in window is [sizeof_collection [get_timing_paths -slack_lesser_than $slackWin -max_paths 1000]]"
	#puts "Arrival time is [get_attribute [get_timing_paths] arrival], required was $arrivalTime"

	set end_time [expr (([clock clicks] - $start_time) / 100000 ) / 10.0]
	puts "Elapsed time : $end_time s"
	
	set power_after [ total_leak_power ]

	#puts "Leakage power after optimization is $power_after"
	#puts "Power saved: [expr $power_before - $power_after]"

	set return_leak [expr 1 - ($power_after / $power_before) ]

	puts "Power saved: $return_leak"

	# Final checks (debug)

	#report_timing

	set percent [get_gate_percentage]
	puts "LVT cells : [lindex $percent 0]"
	puts "HVT cells : [lindex $percent 1]"

	

	#report_threshold_voltage_group

	puts "index =[expr sqrt( (1 - $return_leak)*(1 - $return_leak) + ($end_time * $end_time))]"

	return [list $return_leak $end_time [lindex $percent 0] [lindex $percent 1]]
	
}

proc cell_swapper { cellName Vt_type } {
		#puts "Working on $cellName"
		if [string equal $Vt_type HVT] {
			set newRef [regsub -all {_LL} [get_attribute $cellName ref_name] {_LH}]
			#puts "Assigning new ref_name : $newRef"
			size_cell $cellName CORE65LPHVT_nom_1.00V_25C.db:CORE65LPHVT/$newRef
		} elseif [string equal $Vt_type LVT] {
			set newRef [regsub -all {_LH} [get_attribute $cellName ref_name] {_LL}]
			#puts "Assigning new ref_name to $cellName : $newRef"
			size_cell $cellName CORE65LPLVT_nom_1.00V_25C.db:CORE65LPLVT/$newRef
		} else {
			puts "Bad argument : $Vt_type"
			return 0		
		}
	return 1
}
	

proc leak_power {cell_name} {
  set report_text ""  ;# Contains the output of the report_power command
  set lnr 3           ;# Leakage info is in the 2nd line from the bottom
  set wnr 7           ;# Leakage info is the eighth word in the $lnr line 
  redirect -variable report_text {report_power -only $cell_name -cell -nosplit}
  set report_text [split $report_text "\n"]
  set power_w_unit [lindex [regexp -inline -all -- {\S+} [lindex $report_text [expr [llength $report_text] - $lnr]]] $wnr]
  set w_pos [string first "W" $power_w_unit]
  set unit [string index $power_w_unit [expr $w_pos - 1]]
  set power [string range $power_w_unit 0 [expr $w_pos - 2]]
  if { $unit eq "p" } {
    set power [expr $power / 1000]
  } elseif { $unit eq "u"} {
  	set power [expr $power * 1000]
  }
  return $power
}

proc total_leak_power {} {
	set report_text ""
	set lnr 3
	set wnr 7
	redirect -variable report_text {report_power -cell -nosplit}
	set report_text [split $report_text "\n"]
	set power_w_unit [lindex [regexp -inline -all -- {\S+} [lindex $report_text [expr [llength $report_text] - $lnr]]] $wnr]
	  set w_pos [string first "W" $power_w_unit]
	  set unit [string index $power_w_unit [expr $w_pos - 1]]
	  set power [string range $power_w_unit 0 [expr $w_pos - 2]]
	  if { $unit eq "p" } {
	    set power [expr $power / 1000]
	  } elseif { $unit eq "u"} {
	  	set power [expr $power * 1000]
	  }
 	 return $power
}

proc get_gate_percentage {} {
	# lines are 12(LVT) and 13(HVT) from the bottom
	set report_text ""
	set lnr 13
	set wnr 2
	redirect -variable report_text {report_threshold_voltage_group -nosplit}
	set report_text [split $report_text "\n"]
	set LVT_percent [string trim [lindex [regexp -inline -all -- {\S+} [lindex $report_text [expr [llength $report_text] - $lnr]]] $wnr] "(%)"]
	set lnr 14
	set HVT_percent [string trim [lindex [regexp -inline -all -- {\S+} [lindex $report_text [expr [llength $report_text] - $lnr]]] $wnr] "(%)"]
	set LVT_percent [expr $LVT_percent / 100]
	set HVT_percent [expr $HVT_percent / 100]
	return [list $LVT_percent $HVT_percent]
}

proc swap_all_LVT {} {
	foreach_in_collection cell [get_cells] {
		set cell_name [get_attribute $cell full_name]
		cell_swapper $cell_name LVT
	}
	return 1
}

#leakage_opt 5 5 1
