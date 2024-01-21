########################################################################
# Copyright (C) 2020-2023 Fulvio Benini
#
# This file is part of Scid (Shane's Chess Information Database).
# Scid is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.

### Window for chess engine configuration and position analysis

namespace eval enginewin {}
array set ::enginewin::engState {} ; # closed disconnected idle run locked

# Return a list contatining the engine's ID, engine's name and true if it is running.
# Return only the engines in idle or run state.
proc ::enginewin::listEngines {} {
    set result {}
    foreach {id state} [array get ::enginewin::engState] {
        if {$state ni {idle run}} { continue }
        lassign [set ::enginewin::engConfig_$id] name
        lappend result [list $id $name [expr { $state eq "run" ? 1 : 0 }] ]
    }
    return $result
}

# Sends the updated position to the active engines
proc ::enginewin::onPosChanged { {ids ""}} {
    set position ""
    foreach {id state} [array get ::enginewin::engState] {
        if {$state ni {run autoplay_run}} { continue }
        if {$ids ne "" && $id ni $ids} { continue }
        if {$position eq ""} {
            set position [sc_game UCI_currentPos]
        }
        ::enginewin::sendPosition $id $position
    }
}

# Sends a position to an engine.
# When the engine replies with an InfoGo message the state will change to "run".
proc ::enginewin::sendPosition {id position} {
    ::enginewin::updateDisplay $id ""
    if {[set ::enginewin::newgame_$id]} {
        set ::enginewin::newgame_$id false
        ::engine::send $id NewGame [list analysis post_pv post_wdl [sc_game variant]]
    }
    ::engine::send $id Go [list $position [set ::enginewin::limits_$id]]
}

# Start an engine (if necessary it will opens a new enginewin window).
# Return the engine's id.
proc ::enginewin::start { {id ""} {enginename ""} } {
    if {$id eq "" || ![winfo exists .engineWin$id]} {
        set id [::enginewin::Open $id $enginename]
        catch {
           ::enginewin::sendPosition $id [sc_game UCI_currentPos]
        }
    } elseif {$::enginewin::engState($id) eq "idle"} {
        ::enginewin::sendPosition $id [sc_game UCI_currentPos]
    }
    return $id
}

# Stop the engine.
# Return true if a StopGo message was sent to the engine.
proc ::enginewin::stop {id} {
    if {[winfo exists .engineWin$id] && $::enginewin::engState($id) in {run autoplay_run locked}} {
        ::engine::send $id StopGo
        return true
    }
    return false
}

# If the engine is running, stop it. Otherwise invoke ::enginewin::start
# Return the engine's id.
proc ::enginewin::toggleStartStop { {id ""} {enginename ""} } {
    if { $::enginewin::finishGameMode } {
        set ::enginewin::finishGameMode 0
        ::enginewin::stop 1
        ::enginewin::stop 2
        return $id
    } elseif {[::enginewin::stop $id]} {
        return $id
    }
    return [::enginewin::start $id $enginename]
}

proc ::enginewin::Open { {id ""} {enginename ""} } {
    if {$id == ""} {
        set id 1
        while {[winfo exists .engineWin$id]} {
            incr id
        }
    }
    set w .engineWin$id
    if {! [::win::createWindow $w ""]} {
        ::win::makeVisible $w
        return
    }

    # The main windows is divided in three parts:
    # - at the top $w.header_info which shows time, nps, etc...
    # - at the bottom the buttons bar
    # - in the middle $w.main which is further divided in three parts:
    #   - top-left: $w.display where the pv lines are shown
    #   - bottom-left: $w.debug where all the engine's i/o is shown
    #   - right: $w.config with all the engine options.
    # $w.debug can be hidden and $w.display would expand downward.
    # $w.config can be hidden and $w.display and eventually $w.debug would expand rightward.

    ttk::frame $w.header_info
    ttk_text $w.header_info.text -style Toolbutton -wrap word -height 1 -pady 2
    autoscrollBars y $w.header_info $w.header_info.text

    ttk::frame $w.main
    ttk::panedwindow $w.pane
    ttk::frame $w.config
    ttk::frame $w.display
    ::enginewin::createDisplayFrame $id $w.display
    $w.pane add $w.display -weight 1
    ttk::frame $w.debug
    ttk_text $w.debug.lines -state disabled
    autoscrollBars y $w.debug $w.debug.lines
    grid $w.pane -row 0 -column 0 -in $w.main -sticky news
    grid $w.config -row 0 -column 1 -in $w.main -sticky news -padx {10 0}
    grid rowconfigure $w.main 0 -weight 1
    grid columnconfigure $w.main 0 -weight 1000
    grid columnconfigure $w.main 1 -weight 1

    ttk::frame $w.config.btn
    ::enginewin::createConfigButtons $id $w.config.btn
    ttk::frame $w.config.options
    grid columnconfigure $w.config 0 -weight 1
    grid rowconfigure $w.config 1 -weight 1
    grid $w.config.btn
    grid $w.config.options -sticky news

    ttk::frame $w.btn
    ::enginewin::createButtonsBar $id $w.btn $w.display

    grid $w.header_info -sticky news
    grid $w.main -sticky news
    grid $w.btn -sticky news
    grid rowconfigure $w 0 -weight 0
    grid rowconfigure $w 1 -weight 1
    grid rowconfigure $w 2 -weight 0
    grid columnconfigure $w 0 -weight 1

    bind $w <<NewGame>> "set ::enginewin::newgame_$id true"

    # The engine should be closed before the debug .text is destroyed
    bind $w.config <Destroy> "
        if {\$::enginewin::finishGameMode} {
            set ::enginewin::finishGameMode 0
            ::enginewin::stop 1
            ::enginewin::stop 2
        }
        unset ::enginewin::engState($id)
        ::engine::close $id
        unset ::enginewin::engConfig_$id
        unset ::enginewin::limits_$id
        unset ::enginewin::position_$id
        unset ::enginewin::newgame_$id
        unset ::enginewin::startTime_$id
        ::notify::EngineBestMove $id {} {}
    "

    options.persistent ::enginewin_lastengine($id) ""
    set ::enginewin::engState($id) {}
    set ::enginewin::engConfig_$id {}
    set ::enginewin::limits_$id {}
    set ::enginewin::position_$id ""
    set ::enginewin::newgame_$id true
    set ::enginewin::startTime_$id [clock milliseconds]
    if {![winfo exists ::enginewin::finishGameMode]} {
        set ::enginewin::finishGameMode 0
    }

    if {$enginename eq ""} {
        set enginename $::enginewin_lastengine($id)
    }
    catch { ::enginewin::connectEngine $id $enginename }
    return $id
}

# Creates $w.display, where the pv lines sent by the engine will be shown.
proc ::enginewin::createDisplayFrame {id display} {
    ttk_text $display.pv_lines -exportselection true -padx 4 -state disabled
    autoscrollBars both $display $display.pv_lines
    set tab [font measure font_Regular -displayof $display "xxxxxxx"]
    $display.pv_lines configure -tabs [list [expr {$tab * 2}] right [expr {int($tab * 2.2)}]]
    $display.pv_lines tag configure lmargin -lmargin2 [expr {$tab * 3}]
    $display.pv_lines tag configure markmove -underline 1
    $display.pv_lines tag bind moves <ButtonRelease-1> {
        if {[%W tag ranges sel] eq ""} {
            ::enginewin::exportMoves %W @%x,%y
        }
    }
    $display.pv_lines tag bind moves <Motion> [list apply {{id} {
        %W tag remove markmove 1.0 end
        if {[%W tag ranges sel] eq "" && ![catch {
                # An exception will be thrown if the engine sent an illegal pv
                sc_pos board [set ::enginewin::position_$id] [::enginewin::getMoves %W @%x,%y] } pos]} {
            # TODO:
            # Using wordstart and wordend would be a lot more efficient.
            # However they do not consider the [+.-] chars as part of the word.
            # set movestart [%W index "@%x,%y wordstart"]
            # %W tag add markmove $movestart "$movestart wordend"
            set movestart "[%W search -backwards -regexp {\s} "@%x,%y"] +1chars"
            %W tag add markmove $movestart [%W search " " $movestart]
            ::board::popup .enginewinBoard $pos %X %Y
        } else {
            catch { wm withdraw .enginewinBoard }
        }
    }} $id]
    $display.pv_lines tag bind moves <Any-Leave> {
        %W tag remove markmove 1.0 end
        catch { wm withdraw .enginewinBoard }
    }
}

# Create the buttons used to select an engine and manage the configured engines:
# add a new local or remote engine; reload, clone or delete an existing engine.
proc ::enginewin::createConfigButtons {id w} {
    ttk::combobox $w.engine -width 30 -state readonly -postcommand "
        $w.engine configure -values \[::enginecfg::names \]
    "
    bind $w.engine <<ComboboxSelected>> [list apply {{id} {
        ::enginewin::connectEngine $id [%W get]
    }} $id]
    ::utils::tooltip::Set $w.engine [tr EngineSelect]

    ttk::button $w.addpipe -image tb_eng_add -command [list apply {{id} {
        if {[set newEngine [::enginecfg::dlgNewLocal]] ne ""} {
            ::enginewin::connectEngine $id $newEngine
        }
    }} $id]
    ::utils::tooltip::Set $w.addpipe [tr EngineAddLocal]

    ttk::button $w.addremote -image tb_eng_network -command [list apply {{id} {
        if {[set newEngine [::enginecfg::dlgNewRemote]] ne ""} {
            ::enginewin::connectEngine $id $newEngine
        }
    }} $id]
    ::utils::tooltip::Set $w.addremote [tr EngineAddRemote]

    ttk::button $w.reload -image tb_eng_reload \
        -command "event generate $w.engine <<ComboboxSelected>>"
    ::utils::tooltip::Set $w.reload [tr EngineReload]

    ttk::button $w.clone -image tb_eng_clone -command "
        ::enginewin::connectEngine $id \[::enginecfg::add \$::enginewin::engConfig_$id \]
    "
    ::utils::tooltip::Set $w.clone [tr EngineClone]

    ttk::button $w.delete -image tb_eng_delete -command [list apply {{id} {
        lassign [set ::enginewin::engConfig_$id] name
        if {[::enginecfg::remove $name]} {
            ::enginewin::connectEngine $id {}
        }
    }} $id]
    ::utils::tooltip::Set $w.delete [tr EngineDelete]

    grid $w.engine $w.addpipe $w.addremote \
         $w.reload $w.clone $w.delete -sticky news
}

# Creates the buttons bar
proc ::enginewin::createButtonsBar {id btn display} {
    ttk::button $btn.startStop -image [list tb_eng_on pressed tb_eng_off] -style Toolbutton \
        -command "::enginewin::toggleStartStop $id"
    #TODO: change the tooltip to "Start/stop engine"
    ::utils::tooltip::Set $btn.startStop [tr StartEngine]

    ttk::button $btn.lock -image tb_eng_lock -style Toolbutton -command "
        if {\$::enginewin::engState($id) eq {locked}} {
            ::enginewin::changeState $id run
            ::enginewin::onPosChanged $id
        } else {
            ::enginewin::changeState $id locked
        }
    "
    bind $btn.lock <Any-Enter> [list apply {{id} {
        if {"pressed" in [%W state]} {
            ::board::popup .enginewinBoard [sc_pos board [set ::enginewin::position_$id] ""] %X %Y above
        }
    }} $id]
    bind $btn.lock <Any-Leave> {
        catch { wm withdraw .enginewinBoard }
    }
    ::utils::tooltip::Set $btn.lock [tr LockEngine]

    ttk::button $btn.addbestmove -image tb_eng_addbestmove -style Toolbutton \
        -command "::enginewin::exportMoves $display.pv_lines 1.0"
    ::utils::tooltip::Set $btn.addbestmove [tr AddMove]
    ttk::button $btn.addbestline -image tb_eng_addbestline -style Toolbutton \
        -command "::enginewin::exportMoves $display.pv_lines 1.end"
    ::utils::tooltip::Set $btn.addbestline [tr AddVariation]
    ttk::button $btn.addlines -image tb_eng_addlines -style Toolbutton \
        -command "::enginewin::exportLines $display.pv_lines"
    ::utils::tooltip::Set $btn.addlines [tr AddAllVariations]

    ttk::spinbox $btn.multipv -increment 1 -width 4 -state disabled \
        -validate key -validatecommand { string is integer %P } \
        -command "after idle \[bind $btn.multipv <FocusOut>\]"
    ttk::button $btn.finishgame -image tb_finish_off -style Toolbutton \
        -command "::enginewin::toggleFinishGame $id $btn"
    ::utils::tooltip::Set $btn.finishgame [tr FinishGame]
    bind $btn.multipv <Return> { {*}[bind %W <FocusOut>] }
    bind $btn.multipv <FocusOut> "::enginewin::changeOption $id multipv $btn.multipv"
    ::utils::tooltip::Set $btn.multipv [tr Lines]

    menu $btn.threads_menu
    foreach {threads_value} {1 2 4 8 16 32 64} {
        $btn.threads_menu add command -label "$threads_value CPU" -command \
            "::enginewin::changeOption $id threads $threads_value"
    }
    #TODO: change keyboard focus to the threads widget
    $btn.threads_menu add command -label "..." -command \
        "::enginewin::changeState $id showConfig"
    ttk::menubutton $btn.threads -text "1 CPU" -state disabled \
        -style Toolbutton -direction above -menu $btn.threads_menu

    menu $btn.hash_menu
    foreach {hash_value} {16 64 256 1024 2048 4096 8192} {
        $btn.hash_menu add command -label "$hash_value MB" -command \
            "::enginewin::changeOption $id hash $hash_value"
    }
    #TODO: change keyboard focus to the hash widget
    $btn.hash_menu add command -label "..." -command \
        "::enginewin::changeState $id showConfig"
    ttk::menubutton $btn.hash -text "?? MB" -state disabled \
        -style Toolbutton -direction above -menu $btn.hash_menu

    menu $btn.limits_menu
    foreach {depth_value} {16 20 24 28 32 36 40} {
        $btn.limits_menu add command -label "[tr Depth]: $depth_value" -command \
            "::enginewin::changeOption $id _go_limits \[list \[list depth $depth_value \] \]"
    }
    $btn.limits_menu add command -label "[tr Depth]: ∞" -command \
        "::enginewin::changeOption $id _go_limits {}"
    ttk::menubutton $btn.limits -style Toolbutton -direction above -menu $btn.limits_menu
    trace add variable ::enginewin::limits_$id write [list apply {{btn varname args} {
        set value [set $varname]
        if {$value eq ""} {
            $btn configure -text "[tr Depth]: ∞"
        } else {
            $btn configure -text [string map [list depth "[tr Depth]:"] [join $value]]
        }
    }} $btn.limits]

    ttk::button $btn.config -image tb_eng_config -style Toolbutton \
        -command "::enginewin::changeState $id toggleConfig"
    $btn.config state pressed
    grid $btn.startStop $btn.lock $btn.addbestmove $btn.addbestline \
        $btn.addlines $btn.finishgame $btn.multipv $btn.threads $btn.hash $btn.limits x $btn.config -sticky ew
    grid columnconfigure $btn 10 -weight 1
}

# Sends a SetOptions message to the engine if an option's value is different.
proc ::enginewin::changeOption {id name widget_or_value} {
    set prev_state $::enginewin::engState($id)
    if {$name eq "_go_limits"} {
        set ::enginewin::limits_$id $widget_or_value
        set changed true
    } else {
        set idx [::enginecfg::findOption $id $name]
        if {[winfo exists $widget_or_value]} {
            set changed [::enginecfg::setOptionFromWidget $id $idx $widget_or_value]
        } else {
            set changed [::enginecfg::setOption $id $idx $widget_or_value]
        }
    }
    if {$changed && $prev_state in {run}} {
        ::enginewin::sendPosition $id [set ::enginewin::position_$id]
    }
}

# Sets the current state of the engine and updates the relevant buttons.
# The states are:
# closed -> No engine is open.
# disconnected -> The engine was open but the connection was terminated.
# idle -> The engine is open and ready.
# run -> The engine is analyzing the current position.
# autoplay_idle -> The engine is playing, and finished analyzing a move.
# autoplay_run -> The engine is playing, and analyzing the current position.
# autoplay_gate -> The engine is playing, and the controlling logic is pending on a state change.
#    Used to prevent race conditions, by guaranteeing detection of key state transitions that
#    can otherwise be missed due to execution timing.
# locked -> The engine is analyzing a fixed position.
proc ::enginewin::changeState {id newState} {
    set w .engineWin$id
    if {$newState in {showConfig toggleConfig}} {
        if {[grid info $w.config] eq ""} {
            $w.btn.config state pressed
            grid $w.config
        } elseif {$newState eq "toggleConfig"} {
            $w.btn.config state !pressed
            grid remove $w.config
        }
        return
    }

    if {$::enginewin::finishGameMode} {
        if {$newState eq "idle"} { set newState "autoplay_idle" }
        if {$newState eq "run"} { set newState "autoplay_run" }
    }

    if {$::enginewin::engState($id) eq $newState} { return }

    # Hide the config frame
    # TODO: hide only the first time or if $w.display is hidden or very small
    if {$newState eq "run"} {
        $w.btn.config state !pressed
        grid remove $w.config
    }

    lappend btnDisabledStates [list config.btn.reload closed]
    lappend btnDisabledStates [list config.btn.clone closed]
    lappend btnDisabledStates [list config.btn.delete closed]
    # Buttons that add moves are not disabled when the engine is locked.
    # This allow the user to later add the lines. And if the board position
    # will be different, only the valid moves will be added to the game.
    lappend btnDisabledStates [list btn.addbestmove [list closed disconnected]]
    lappend btnDisabledStates [list btn.addbestline [list closed disconnected]]
    lappend btnDisabledStates [list btn.addlines [list closed disconnected autoplay_idle autoplay_run autoplay_gate]]
    lappend btnDisabledStates [list btn.startStop [list closed disconnected] [list locked run autoplay_idle autoplay_run autoplay_gate]]
    lappend btnDisabledStates [list btn.lock [list closed disconnected idle autoplay_idle autoplay_run autoplay_gate] locked]
    lappend btnDisabledStates [list btn.finishgame [list closed disconnected autoplay_idle autoplay_run autoplay_gate]]

    foreach {elem} $btnDisabledStates {
        lassign $elem btn states pressed
        if {$newState in $states} {
            $w.$btn configure -state disabled
        } else {
            $w.$btn configure -state normal
        }
        if {$newState in $pressed} {
            $w.$btn state pressed
        } else {
            $w.$btn state !pressed
        }
    }
    set ::enginewin::engState($id) $newState

    if {$newState in {closed disconnected idle autoplay_idle locked}} {
        ::notify::EngineBestMove $id "" ""
    }
}

# Invoked when the engine's name changes.
# Update the window's title and ::enginewin_lastengine accordingly.
proc ::enginewin::updateEngineName {id name} {
    set ::enginewin_lastengine($id) $name
    ::setTitle .engineWin$id "[tr Engine]: $name"
    if {$name eq ""} {
        .engineWin$id.config.btn.engine set "[tr Engine]:"
    } else {
        .engineWin$id.config.btn.engine set $name
    }
}

proc ::enginewin::logEngine {id on} {
    catch { .engineWin$id.pane forget .engineWin$id.debug }
    .engineWin$id.debug.lines configure -state normal
    .engineWin$id.debug.lines delete 1.0 end
    .engineWin$id.debug.lines configure -state disabled
    if {$on} {
        .engineWin$id.pane add .engineWin$id.debug -weight 1
        ::engine::setLogCmd $id \
            [list ::enginewin::logHandler $id .engineWin$id.debug.lines "" ""]\
            [list ::enginewin::logHandler $id .engineWin$id.debug.lines header ">>"]
    } else {
        ::engine::setLogCmd $id "" ""
    }
}

proc ::enginewin::logHandler {id widget tag prefix msg} {
    upvar ::enginewin::startTime_$id startTime_
    set t [format "(%.3f) " \
        [expr {( [clock milliseconds] - $startTime_ ) / 1000.0}]]
    $widget configure -state normal
    $widget insert end "$t[set prefix]$msg\n" $tag
    $widget see end
    $widget configure -state disabled
}

# If any, closes the connection with the current engine.
# If "config" is not "" opens a connection with a new engine.
# If necessary, opens a new enginewin window.
proc ::enginewin::connectEngine {id enginename} {
    if {$id eq "" || ![winfo exists .engineWin$id]} {
        set id [::enginewin::Open $id $enginename]
        return;
    }

    set configFrame .engineWin$id.config.options
    foreach wchild [winfo children $configFrame] { destroy $wchild }

    ::engine::close $id
    ::enginewin::logEngine $id false

    set config [::enginecfg::get $enginename]
    lassign $config name cmd args wdir elo time url uci options
    # Update engine's last used time.
    set time [clock seconds]
    set ::enginewin::engConfig_$id [list $name $cmd $args $wdir $elo $time $url $uci {}]

    ::enginewin::updateDisplay $id ""
    ::enginewin::changeState $id closed
    ::enginewin::updateEngineName $id $name

    if {$config eq ""} {
        ::enginecfg::createConfigFrame $id $configFrame \
            "No engine open: select or add one."
        return
    }

    ::enginecfg::createConfigFrame $id $configFrame "$cmd $args\nConnecting..."

    lassign $url scoreside notation pvwrap debugframe priority netport
    ::enginewin::changeDisplayLayout $id notation $notation
    ::enginewin::changeDisplayLayout $id wrap $pvwrap
    ::enginewin::updateOptions $id ""
    ::enginewin::logEngine $id $debugframe

    update idletasks

    switch $uci {
      0 { set protocol "xboard" }
      1 { set protocol "uci" }
      2 { set protocol "network" }
      default { set protocol [list uci xboard] }
    }
    if {[catch {
        if {$wdir != "" && $wdir != "."} {
            set oldwdir [pwd]
            cd $wdir
        }
        ::engine::connect $id [list ::enginewin::callback $id] $cmd $args $protocol
        if {[info exists oldwdir]} {
            cd $oldwdir
        }
    } errorMsg]} {
        return [::enginewin::callback $id [list InfoDisconnected [list $errorMsg]]]
    }

    if {[catch { ::enginecfg::setupNetd $id $netport }]} {
        ERROR::MessageBox
    }

    if {[llength $options]} {
        ::engine::send $id SetOptions $options
    }
    # Send a NewGame message to receive InfoReady when the engine completes the initialization.
    ::engine::send $id NewGame [list {}]
    # But also schedule a NewGame message, that depends on the position, when the engine starts.
    set ::enginewin::newgame_$id true
}

# Receive the engine's messages
proc ::enginewin::callback {id msg} {
    set configFrame .engineWin$id.config.options
    lassign $msg msgType msgData
    switch $msgType {
        "InfoConfig" {
            ::enginewin::updateOptions $id $msgData
            set renamed [::enginecfg::updateConfigFrame $id $configFrame $msgData]
            if {$renamed ne ""} {
                ::enginewin::updateEngineName $id $renamed
            }
            ::enginewin::changeState $id idle
        }
        "InfoGo" {
            lassign $msgData ::enginewin::position_$id ::enginewin::limits_$id
            ::enginewin::changeState $id run
        }
        "InfoBestMove" {
            if {$::enginewin::finishGameMode} {
                ::enginewin::changeState $id idle
                set ::enginewin::finishGameEngineDone$id true
                set ::enginewin::finishGameEngineBestMove$id $msgData
            }
        }
        "InfoPV" {
            ::enginewin::updateDisplay $id $msgData
        }
        "InfoReady" {
            ::enginecfg::autoSaveConfig $id $configFrame true
            ::enginewin::changeState $id idle
        }
        "InfoDisconnected" {
            ::enginewin::updateOptions $id ""
            ::enginecfg::autoSaveConfig $id $configFrame false
            ::enginecfg::updateConfigFrame $id $configFrame {}
            ::enginewin::changeState $id disconnected
            lassign $msgData errorMsg
            if {$errorMsg eq ""} {
                set errorMsg "The connection with the engine terminated unexpectedly."
            }
            tk_messageBox -icon warning -type ok -parent . -message $errorMsg
        }
    }
}

proc ::enginewin::changeDisplayLayout {id param value} {
    upvar ::enginewin::engConfig_$id engConfig_
    set w .engineWin$id
    switch $param {
        "notation" {
            set idx 1
            if {$value < 0} {
                set value [expr { 0 - $value }]
            }
            # If it is an xboard engine with san=1 store it as a negative value
            foreach elem [lsearch -all -inline -index 0 [lindex $engConfig_ 8] "san"] {
                if {[lindex $elem 7]} {
                    set value [expr { 0 - $value }]
                    break
                }
            }
        }
        "wrap" {
            set idx 2
            $w.display.pv_lines configure -wrap $value
        }
        default { error "changeDisplayLayout unknown $param" }
    }
    lset engConfig_ 6 $idx $value
}

proc ::enginewin::updateOptions {id msgData} {
    set w .engineWin$id
    if {$msgData eq ""} {
        $w.btn.multipv set ""
        $w.btn.multipv configure -state disabled
        $w.btn.threads configure -state disabled -text "1 CPU"
        $w.btn.hash configure -state disabled -text "?? MB"
        return
    }
    lassign $msgData protocol netclients options
    for {set i 0} {$i < [llength $options]} {incr i} {
        lassign [lindex $options $i] name value type default min max var_list internal
        if {$internal || $type in [list button save reset]} { continue }

        if {[string equal -nocase $name "multipv"] && $min ne "" && $max ne ""} {
            $w.btn.multipv configure -state normal -from $min -to $max -style {}
            $w.btn.multipv set $value
        } elseif {[string equal -nocase $name "threads"]} {
            $w.btn.threads configure -state normal -text "$value CPU"
        } elseif {[string equal -nocase $name "hash"]} {
            $w.btn.hash configure -state normal -text "$value MB"
        }
    }
}

proc ::enginewin::updateDisplay {id msgData} {
    lassign $msgData multipv depth seldepth nodes nps hashfull tbhits time score score_type score_wdl pv
    if {$time eq ""} { set time 0 }
    if {$nps eq ""} { set nps 0 }
    if {$hashfull eq ""} { set hashfull 0 }
    if {$tbhits eq ""} { set tbhits 0 }

    set w .engineWin$id
    $w.header_info.text configure -state normal
    $w.header_info.text delete 1.0 end
    $w.header_info.text insert end "[tr Time]: " header
    $w.header_info.text insert end [format "%.2f s" [expr {$time / 1000.0}]]
    $w.header_info.text insert end "   [tr Nodes]: " header
    $w.header_info.text insert end [format "%.2f Kn/s" [expr {$nps / 1000.0}]]
    $w.header_info.text insert end "   Hash: " header
    $w.header_info.text insert end [format "%.1f%%" [expr {$hashfull / 10.0}]]
    $w.header_info.text insert end "   TB Hits: " header
    $w.header_info.text insert end $tbhits
    $w.header_info.text configure -state disabled

    set w .engineWin$id.display
    $w.pv_lines configure -state normal
    if {$msgData eq ""} {
        $w.pv_lines delete 1.0 end
        $w.pv_lines configure -state disabled
        return
    }

    lassign [lindex [set ::enginewin::engConfig_$id] 6] scoreside notation
    if {[catch {

    set translated untranslated
    if {$notation > 0} {
        set pv [sc_pos coordToSAN [set ::enginewin::position_$id] $pv]
    }
    if {$notation == 1 || $notation == -1} {
        set pv [::trans $pv]
        set translated translated
    } elseif {$notation == 3 || $notation == -3} {
        # Figurine
        set pv [string map {K "\u2654" Q "\u2655" R "\u2656" B "\u2657" N "\u2658"} $pv]
    }

    }]} {
        set pv "illegal_pv! $pv"
    }

    if {$score ne ""} {
        if {$scoreside eq "white" && [sc_pos side] eq "black"} {
            set score [expr { - $score }]
        }
        if {$score_type eq "mate"} {
            if {$score >= 0} {
                set score "+M$score"
            } else {
                set score "-M[string range $score 1 end]"
            }
        } else {
            set score [format "%+.2f" [expr {$score / 100.0}]]
            if {$score_type eq "lowerbound" || $score_type eq "upperbound"} {
                lappend extraInfo $score_type
            }
        }
    }
    if {$seldepth ne ""} {
        set depth "$depth/$seldepth"
    }
    if {$score_wdl ne ""} {
        lassign $score_wdl win draw lose
        if {$draw eq ""} { set draw 0 }
        if {$lose eq ""} { set lose 0 }
        lappend extraInfo [format "W: %.1f%%" [expr {$win / 10.0}]]
        lappend extraInfo [format "D: %.1f%%" [expr {$draw / 10.0}]]
        lappend extraInfo [format "L: %.1f%%" [expr {$lose / 10.0}]]
    }
    if {$nodes ne ""} {
        if {$nodes > 100000000} {
            lappend extraInfo [format "%.2fM nodes" [expr {$nodes / 1000000.0}]]
        } else {
            lappend extraInfo [format "%.2fK nodes" [expr {$nodes / 1000.0}]]
        }
    }
    set pvline ""
    # End of the first move: first space after the first alpha char
    regexp {^(.*?[A-Za-z].*?)(\s.*)$} $pv -> pv pvline

    set line $multipv
    if {$multipv == 1} {
        # Previous line nr. 1 is now obsolete
        $w.pv_lines tag remove header 1.0 1.end
    }
    # If the engine has repeatedly sent multipv 1, do not delete the obsolete lines
    catch { $w.pv_lines tag nextrange header 2.0 } multilines
    if {$line > 1 || $multilines ne ""} {
        # Multipv lines >= than the current one are now obsolete and deleted.
        $w.pv_lines delete $line.0 end
    }
    $w.pv_lines insert $line.0 "\n"
    $w.pv_lines insert $line.end "$depth\t"
    $w.pv_lines insert $line.end "$score" header
    $w.pv_lines insert $line.end "\t"
    $w.pv_lines insert $line.end "$pv" [list header moves $translated]
    $w.pv_lines insert $line.end "$pvline" [list lmargin moves]
    if {[info exists extraInfo]} {
        $w.pv_lines insert $line.end "  ([join $extraInfo {  }])" lmargin
    }

    $w.pv_lines configure -state disabled
    if {$line == 1 && $::enginewin::engState($id) ne "locked"} {
        if {$scoreside eq "engine" && [sc_pos side] eq "black" && $score ne ""} {
            set sign_reversed [expr { [string index $score 0] eq "+" ? "-" : "+" }]
            set score "$sign_reversed[string range $score 1 end]"
        }
        if {$notation == 2 || $notation == -2} {
            set best_move [::trans $pv]
        } else {
            set best_move $pv
        }
        ::notify::EngineBestMove $id $best_move $score
    }
}

# Retrieve the moves at the line specified by index.
# An index linenumber.0 can be used to retrive just the first move.
# An index linenumber.end can be used to retrive all the moves.
# If index is not valid an exception is raised.
proc ::enginewin::getMoves {w index} {
    lassign [$w tag nextrange moves "$index linestart"] begin end
    if {[regexp {^\d+\.0$} $index]} {
        set end [$w search " " $begin]
    } elseif {![regexp {^\d+\.end$} $index]} {
        set end [$w search " " $index]
    }
    if {[$w tag nextrange translated $begin $end] eq ""} {
        set moves [$w get $begin $end]
    } else {
        set moves [::untrans [$w get $begin $end]]
    }
    return [string map {"\u2654" K "\u2655" Q "\u2656" R "\u2657" B "\u2658" N} $moves]
}

# Add the moves to the current game
# An index linenumber.0 can be used to add just the first move.
# An index linenumber.end can be used to add all the moves.
# Return false if index is not valid.
proc ::enginewin::exportMoves {w index} {
    if {[catch {::enginewin::getMoves $w $index} line]} {
        return false
    }
    ::undoFeature save
    sc_game import $line
    ::notify::GameChanged
    return true
}

# Add all the move lines to the current game.
proc ::enginewin::exportLines {w} {
    set i_line 1
    set location [sc_move pgn]
    while {![catch {::enginewin::getMoves $w $i_line.end} line]} {
        # When multipv is 1, the old lines are also shown, but do not export them
        lassign [$w tag nextrange header "$i_line.end linestart"] is_latest
        if {$is_latest eq ""} { break }
        if {$i_line == 1} { ::undoFeature save }
        sc_game import $line
        sc_move pgn $location
        incr i_line
    }
    ::notify::GameChanged
}

################################################################################
# will ask engine(s) to play the game till the end
################################################################################
proc ::enginewin::toggleFinishGame { id btn } {
    set engine1_available [winfo exists .engineWin1]
    set engine2_available [winfo exists .engineWin2]

    if {$engine1_available} {
        ::enginewin::stop 1
        set config [::enginecfg::get $::enginewin_lastengine(1)]
        if {$config ne ""} {
            lassign $config name1 cmd1 args1 wdir1 elo1 time1 url1 uci1 options1
        } else {
            set uci1 0
        }
        unset config
        set engine1_available [expr {$engine1_available && $uci1}]
    }

    if {$engine2_available} {
        ::enginewin::stop 2
        set config [::enginecfg::get $::enginewin_lastengine(2)]
        if {$config ne ""} {
            lassign $config name2 cmd2 args2 wdir2 elo2 time2 url2 uci2 options2
        } else {
            set uci2 0
        }
        unset config
        set engine2_available [expr {$engine2_available && $uci2}]
    }

    # Default values
    if {! [info exists ::enginewin::finishGameEng1] } { set ::enginewin::finishGameEng1 1 }
    if {! [info exists ::enginewin::finishGameEng2] } { set ::enginewin::finishGameEng2 1 }
    if {! [info exists ::enginewin::finishGameCmd1] } { set ::enginewin::finishGameCmd1 "movetime" }
    if {! [info exists ::enginewin::finishGameCmdVal1] } { set ::enginewin::finishGameCmdVal1 5 }
    if {! [info exists ::enginewin::finishGameCmd2] } { set ::enginewin::finishGameCmd2 "movetime" }
    if {! [info exists ::enginewin::finishGameCmdVal2] } { set ::enginewin::finishGameCmdVal2 5 }

    set w .configFinishGame
    win::createDialog $w
    wm resizable $w 0 0
    ::setTitle $w "Scid: $::tr(FinishGame)"

    ttk::labelframe $w.wh_f -text "$::tr(White)" -padding 5
    grid $w.wh_f -column 0 -row 0 -columnspan 2 -sticky we -pady 8
    foreach psize $::boardSizes {
        if {$psize >= 40} { break }
    }
    ttk::label $w.wh_f.p -image wk$psize
    grid $w.wh_f.p -column 0 -row 0 -rowspan 3
    if {$engine1_available} {
        ttk::radiobutton $w.wh_f.e1 -text $name1 -variable ::enginewin::finishGameEng1 -value 1
    } else {
        set ::enginewin::finishGameEng1 2
        ttk::radiobutton $w.wh_f.e1 -text $::tr(StartEngine) -variable ::enginewin::finishGameEng1 -value 1 -state disabled
    }
    if {$engine2_available } {
        ttk::radiobutton $w.wh_f.e2 -text $name2 -variable ::enginewin::finishGameEng1 -value 2
    } else {
        set ::enginewin::finishGameEng1 1
        ttk::radiobutton $w.wh_f.e2 -text $::tr(StartEngine) -variable ::enginewin::finishGameEng1 -value 2 -state disabled
    }
    grid $w.wh_f.e1 -column 1 -row 0 -columnspan 3 -sticky w
    grid $w.wh_f.e2 -column 1 -row 1 -columnspan 3 -sticky w
    ttk::spinbox $w.wh_f.cv -width 3 -textvariable ::enginewin::finishGameCmdVal1 -from 1 -to 1000 -justify right
    ttk::radiobutton $w.wh_f.c1 -text $::tr(seconds) -variable ::enginewin::finishGameCmd1 -value "movetime"
    ttk::radiobutton $w.wh_f.c2 -text $::tr(FixedDepth) -variable ::enginewin::finishGameCmd1 -value "depth"
    grid $w.wh_f.cv -column 1 -row 2 -sticky w
    grid $w.wh_f.c1 -column 2 -row 2 -sticky w -padx 6
    grid $w.wh_f.c2 -column 3 -row 2 -sticky w

    ttk::labelframe $w.bk_f -text "$::tr(Black)" -padding 5
    grid $w.bk_f -column 0 -row 1 -columnspan 2 -sticky we -pady 8
    ttk::label $w.bk_f.p -image bk$psize
    grid $w.bk_f.p -column 0 -row 0 -rowspan 3
    if {$engine1_available} {
        ttk::radiobutton $w.bk_f.e1 -text $name1 -variable ::enginewin::finishGameEng2 -value 1
    } else {
        set ::enginewin::finishGameEng2 2
        ttk::radiobutton $w.bk_f.e1 -text $::tr(StartEngine) -variable ::enginewin::finishGameEng2 -value 1 -state disabled
    }
    if {$engine2_available } {
        ttk::radiobutton $w.bk_f.e2 -text $name2 -variable ::enginewin::finishGameEng2 -value 2
    } else {
        set ::enginewin::finishGameEng2 1
        ttk::radiobutton $w.bk_f.e2 -text $::tr(StartEngine) -variable ::enginewin::finishGameEng2 -value 2 -state disabled
    }
    grid $w.bk_f.e1 -column 1 -row 0 -columnspan 3 -sticky w
    grid $w.bk_f.e2 -column 1 -row 1 -columnspan 3 -sticky w
    ttk::spinbox $w.bk_f.cv -width 3 -textvariable ::enginewin::finishGameCmdVal2 -from 1 -to 1000 -justify right
    ttk::radiobutton $w.bk_f.c1 -text $::tr(seconds) -variable ::enginewin::finishGameCmd2 -value "movetime"
    ttk::radiobutton $w.bk_f.c2 -text $::tr(FixedDepth) -variable ::enginewin::finishGameCmd2 -value "depth"
    grid $w.bk_f.cv -column 1 -row 2 -sticky w
    grid $w.bk_f.c1 -column 2 -row 2 -sticky w -padx 6
    grid $w.bk_f.c2 -column 3 -row 2 -sticky w

    ttk::frame $w.fbuttons
    ttk::button $w.fbuttons.cancel -text $::tr(Cancel) -command {
        destroy .configFinishGame
    }
    ttk::button $w.fbuttons.ok -text "OK" -command {
        set ::enginewin::finishGameMode 1
        destroy .configFinishGame
    }
    packbuttons right $w.fbuttons.cancel $w.fbuttons.ok
    grid $w.fbuttons -row 2 -column 1 -columnspan 2 -sticky we
    focus $w.fbuttons.ok
    bind $w <Escape> { .configFinishGame.cancel invoke }
    bind $w <Return> { .configFinishGame.ok invoke }

    ::tk::PlaceWindow $w widget .engineWin$id
    grab $w
    bind $w <ButtonPress> {
        set w .configFinishGame
        if {%x < 0 || %x > [winfo width $w] || %y < 0 || %y > [winfo height $w] } { ::tk::PlaceWindow $w pointer }
    }
    tkwait window $w
    if {!$::enginewin::finishGameMode} { return }

    if { $::enginewin::finishGameEng1 eq "1" } {
        set ::enginewin::finishGameEngName1 $name1
    } else {
        set ::enginewin::finishGameEngName1 $name2
    }
    if { $::enginewin::finishGameEng2 eq "1" } {
        set ::enginewin::finishGameEngName2 $name1
    } else {
        set ::enginewin::finishGameEngName2 $name2
    }

    set ::enginewin::finishGameEngPlayer1 "white"
    set ::enginewin::finishGameEngPlayer2 "black"

    set tmp [sc_pos getComment]
    sc_pos setComment "$tmp $::tr(FinishGame) $::tr(White): $::enginewin::finishGameEngName1 $::tr(Black): $::enginewin::finishGameEngName2"

    # start engines
    set current_engine $::enginewin::finishGameEng1
    foreach {current_cmd} {1 2} {
        ::enginewin::connectEngine $current_engine [set ::enginewin::finishGameEngName$current_cmd]
        set pv_lines$current_cmd .engineWin$current_engine.display.pv_lines
        .engineWin$current_engine.btn.finishgame configure -image tb_finish_on
        # wait for engine
        while { $::enginewin::engState($current_engine) != "autoplay_idle" } {
            if {!$::enginewin::finishGameMode} { break }
            vwait ::enginewin::engState($current_engine)
        }
        set ::enginewin::limits_$current_engine "infinite"
        ::enginewin::sendPosition $current_engine [sc_game UCI_currentPos]
        # Need to make sure the engine is ready to run. Reaching the idle state does not
        # guarantee this due to various commands that may still be in the send queue.
        while { $::enginewin::engState($current_engine) != "autoplay_run" } {
            if {!$::enginewin::finishGameMode} { break }
            vwait ::enginewin::engState($current_engine)
        }
        ::enginewin::stop $current_engine
        # wait for engine to stop
        while { $::enginewin::engState($current_engine) != "autoplay_idle" } {
            if {!$::enginewin::finishGameMode} { break }
            vwait ::enginewin::engState($current_engine)
        }
        # queue a new game for both engines for a fair start:
        ::enginewin::changeState $current_engine "autoplay_gate"
        ::engine::send $current_engine NewGame [list analysis post_pv post_wdl [sc_game variant]]
        # wait for InfoReady
        while { $::enginewin::engState($current_engine) != "autoplay_idle" } {
            if {!$::enginewin::finishGameMode} { break }
            vwait ::enginewin::engState($current_engine)
        }

        set ::enginewin::limits_$current_engine [concat [set ::enginewin::finishGameCmd$current_cmd] [set ::enginewin::finishGameCmdVal$current_cmd]]
        if {[set ::enginewin::finishGameCmd$current_cmd] == "movetime" } { append ::enginewin::limits_$current_engine "000" }

        set ::enginewin::finishGameEng$current_cmd $current_engine

        incr current_engine
        if {$current_engine > 2} { set current_engine 1 }
    }

    set ::enginewin::finishGameMode 1

    while { [string index [sc_game info previousMove] end] != "#"} {
        if {[sc_pos side] == "white"} {
            set current_cmd 1
            set current_engine $::enginewin::finishGameEng1
            set current_player $::enginewin::finishGameEngPlayer1
        } else {
            set current_cmd 2
            set current_engine $::enginewin::finishGameEng2
            set current_player $::enginewin::finishGameEngPlayer2
        }

        # Transition to gate state to prevent missing run->idle transition.
        ::enginewin::changeState $current_engine "autoplay_gate"
        if {!$::enginewin::finishGameMode} { break }
        if { $::enginewin::engState($current_engine) ne "autoplay_gate"  || $current_player != [sc_pos side] } {
            ::enginewin::stop $current_engine
            continue
        }

        set ::enginewin::finishGameEngineDone$current_engine false
        ::enginewin::sendPosition $current_engine [sc_game UCI_currentPos]

        # wait for engine
        while { $::enginewin::engState($current_engine) in { autoplay_run autoplay_gate } } {
            if { $current_player != [sc_pos side] } { break }
            vwait ::enginewin::engState($current_engine)
            if {!$::enginewin::finishGameMode} { break }
        }

        # Check for autoplay exit or forced move.
        if {!$::enginewin::finishGameMode} { break }
        if { $current_player != [sc_pos side] } {
            ::enginewin::stop $current_engine
            continue
        }

        # Must use the best move returned by the engine, not the best move returned by pv_lines.
        # Otherwise, engine strength limiting features (UCI_LimitStrength, Level, ect) may not work.
        # Try getting this info from pv_lines as a backup, if the engine did not send a best move.
        if { [set ::enginewin::finishGameEngineDone$current_engine] } {
            ::undoFeature save
            sc_game import [ set ::enginewin::finishGameEngineBestMove$current_engine]
            ::notify::PosChanged -pgn
        } elseif { ![::enginewin::exportMoves [ set pv_lines$current_cmd ] 1.0] } { break }
    }

    set ::enginewin::finishGameMode 0

    if {[winfo exists .engineWin1]} {
        ::enginewin::stop 1
        if {$::enginewin::engState(1) in { autoplay_idle autoplay_gate }} {
            ::enginewin::changeState 1 "idle"
        }
        .engineWin1.btn.finishgame configure -image tb_finish_off
    }

    if {[winfo exists .engineWin2]} {
        ::enginewin::stop 2
        if {$::enginewin::engState(2) in { autoplay_idle autoplay_gate }} {
            ::enginewin::changeState 2 "idle"
        }
        .engineWin2.btn.finishgame configure -image tb_finish_off
    }
}
