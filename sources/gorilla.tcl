#! /bin/sh
# the next line restarts using wish \
exec tclsh8.5 "$0" ${1+"$@"}

#
# ----------------------------------------------------------------------
# Password Gorilla, a password database manager
# Copyright (c) 2005-2009 Frank Pilhofer
# Copyright (c) 2010 Zbigniew Diaczyszyn
# modified for use with wish8.5, ttk-Widgets and with German localisation
# modified GUI to work without bwidget
# z.dia@gmx.de
# tested with ActiveTcl 8.5.7
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# ----------------------------------------------------------------------
#
# pushed to http:/github.com/zdia/gorilla

package provide app-gorilla 1.0

set ::gorillaVersion {$Revision: 1.5.3.2 $}
set ::gorillaDir [file dirname [info script]]

# ----------------------------------------------------------------------
# Make sure that our prerequisite packages are available. Don't want
# that to fail with a cryptic error message.
# ----------------------------------------------------------------------
#

if {[catch {package require Tk 8.5} oops]} {
		#
		# Someone's trying to run this application with pure Tcl and no Tk.
		#

		puts "This application requires Tk 8.5, which does not seem to be available. \
			You are working with [info patchlevel]"
		puts $oops
		exit 1
}

option add *Dialog.msg.font {Sans 9}
option add *Dialog.msg.wrapLength 6i
# option add *Font "Sans 8"
# option add *Button.Font "Sans 8"

if {[catch {package require Tcl 8.5}]} {
		wm withdraw .
		tk_messageBox -type ok -icon error -default ok \
			-title "Need more recent Tcl/Tk" \
			-message "The Password Gorilla requires at least Tcl/Tk 8.5\
			to run. This smells like Tcl/Tk [info patchlevel].\
			Please upgrade."
		exit 1
}

#
# The isaac package should be in the current directory
#

foreach file {isaac.tcl} {
	if {[catch {source [file join $::gorillaDir $file]} oops]} {
# puts $oops
		wm withdraw .
		tk_messageBox -type ok -icon error -default ok \
			-title "Need $file" \
			-message "The Password Gorilla requires the \"$file\"\
			package. This seems to be an installation problem, as\
			this file ought to be part of the Password Gorilla\
			distribution."
		exit 1
	}
}

#
# Itcl 3.4 is in an subdirectory available to auto_path
# The environment variable ::env(ITCL_LIBRARY) is set 
# to the subdirectory Itcl3.4 in the pkgindex.tcl
# This is necessary for the embedded standalone version in MacOSX
#

if {[tk windowingsystem] == "aqua"}	{
	# set auto_path /Library/Tcl/teapot/package/macosx-universal/lib/Itcl3.4
	set auto_path ""
}

# foreach testitdir [glob -nocomplain [file join $::gorillaDir itcl*]] {
	# if {[file isdirectory $testitdir]} {
		# lappend auto_path $testitdir
	# }
# }

#
# The pwsafe, blowfish, twofish and sha1 packages are in subdirectories
#

foreach subdir {sha1 blowfish twofish pwsafe itcl3.4 msgs} {
	set testDir [file join $::gorillaDir $subdir]
	if {[file isdirectory $testDir]} {
		lappend auto_path $testDir
	}
}

if {[catch {package require msgcat} oops]} {
		puts "error: $oops"
		exit 1
}
namespace import msgcat::*
# mcload [file join $::gorillaDir msgs]

#
# Look for Itcl
#

if {[catch {package require Itcl} oops]} {
	#
	# Itcl is included in tclkit and ActiveState...
	#
	wm withdraw .
	tk_messageBox -type ok -icon error -default ok \
		-title "Need \[Incr Tcl\]" \
		-message "The Password Gorilla requires the \[incr Tcl\]\
		add-on to Tcl. Please install the \[incr Tcl\] package."
	exit 1
}

if {[catch {package require pwsafe} oops]} {
	wm withdraw .
	tk_messageBox -type ok -icon error -default ok \
		-title "Need PWSafe" \
		-message "The Password Gorilla requires the \"pwsafe\" package.\
		This seems to be an installation problem, as the pwsafe package\
		ought to be part of the Password Gorilla distribution."
	exit 1
}

#
# If installed, we can use the uuid package (part of Tcllib) to generate
# UUIDs for new logins, but we don't depend on it.
#

catch {package require uuid}

#
# ----------------------------------------------------------------------
# Prepare and hide main window
# ----------------------------------------------------------------------
#

namespace eval gorilla {}

if {![info exists ::gorilla::init]} {
		wm withdraw .
		set ::gorilla::init 0
}

# ----------------------------------------------------------------------
# GUI and other Initialization
# ----------------------------------------------------------------------

proc gorilla::Init {} {
		set ::gorilla::status ""
		set ::gorilla::uniquenodeindex 0
		set ::gorilla::dirty 0
		set ::gorilla::overridePasswordPolicy 0
		set ::gorilla::isPRNGInitialized 0
		set ::gorilla::activeSelection 0
		catch {unset ::gorilla::dirName}
		catch {unset ::gorilla::fileName}
		catch {unset ::gorilla::db}
		catch {unset ::gorilla::statusClearId}
		catch {unset ::gorilla::clipboardClearId}
		catch {unset ::gorilla::idleTimeoutTimerId}

		if {[llength [trace info variable ::gorilla::status]] == 0} {
			trace add variable ::gorilla::status write ::gorilla::StatusModified
		}

		# Some default preferences
		# will be overwritten by LoadPreferencesFromRCFile if set

		set ::gorilla::preference(defaultVersion) 3
		set ::gorilla::preference(unicodeSupport) 1
		set ::gorilla::preference(lru) [list]
		# added by zdia
		set ::gorilla::preference(rememberGeometries) 1
		set ::gorilla::preference(lang) en
		set ::gorilla::preference(gorillaIcon) 0
}

# This callback traces writes to the ::gorilla::status variable, which
# is shown in the UI's status line. We arrange for the variable to be
# cleared after some time, so that potentially sensible information
# like "password copied to clipboard" does not show forever.
#

proc gorilla::StatusModified {name1 name2 op} {
	if {![string equal $::gorilla::status ""] && \
		![string equal $::gorilla::status "Ready."] && \
		![string equal $::gorilla::status [mc "Welcome to the Password Gorilla."]]} {
		if {[info exists ::gorilla::statusClearId]} {
			after cancel $::gorilla::statusClearId
		}
		set ::gorilla::statusClearId [after 5000 ::gorilla::ClearStatus]
	} else {
		if {[info exists ::gorilla::statusClearId]} {
			after cancel $::gorilla::statusClearId
		}
	}	
	.status configure -text $::gorilla::status
}

proc gorilla::ClearStatus {} {
	catch {unset ::gorilla::statusClearId}
	set ::gorilla::status ""
}

proc gorilla::InitGui {} {
	# themed widgets do'nt know a resource database
	# option add *Button.font {Helvetica 10 bold}
	# option add *title.font {Helvetica 16 bold}
	option add *Menu.tearOff 0
	
	menu .mbar
	. configure -menu .mbar

# Struktur im menu_desc(ription):
# label	widgetname {item tag command shortcut}

		set meta Control
		set menu_meta Ctrl
		
		if {[tk windowingsystem] == "aqua"}	{
			set meta Command
			# set menu_meta Cmd
			# mac is showing the Apple key icon but app is hanging if a procedure
			# is calling a vwait loop. So we just show the letter. Both meta keys
			# are working later on (Tk 8.5.8)
			set menu_meta ""
		}

set ::gorilla::menu_desc {
	File	file	{"New ..." {} gorilla::New "" ""
							"Open ..." {} "gorilla::Open" $menu_meta O
							"Merge ..." open gorilla::Merge "" ""
							Save save gorilla::Save $menu_meta S
							"Save As ..." open gorilla::SaveAs "" ""
							separator "" "" "" ""
							"Export ..." open gorilla::Export "" ""
							separator mac "" "" ""
							"Preferences ..." mac gorilla::Preferences "" ""
							separator mac "" "" ""
							Exit mac gorilla::Exit $menu_meta X
							}	
	Edit	edit	{"Copy Username" login gorilla::CopyUsername $menu_meta U
							"Copy Password" login gorilla::CopyPassword $menu_meta P
							"Copy URL" login gorilla::CopyURL $menu_meta W
							separator "" "" "" ""
							"Clear Clipboard" "" gorilla::ClearClipboard $menu_meta C
							separator "" "" "" ""
							"Find ..." open gorilla::Find $menu_meta F
							"Find next" open gorilla::FindNext $menu_meta G
							}
	Login	login	{ "Add Login" open gorilla::AddLogin $menu_meta A
							"Edit Login" open gorilla::EditLogin $menu_meta E
							"View Login" open gorilla::ViewLogin $menu_meta V
							"Delete Login" login gorilla::DeleteLogin "" ""
							"Move Login ..." login gorilla::MoveLogin "" ""
							separator "" "" "" ""
							"Add Group ..." open gorilla::AddGroup "" ""
							"Add Subgroup ..." group gorilla::AddSubgroup "" ""
							"Rename Group ..." group gorilla::RenameGroup "" ""
							"Move Group ..." group gorilla::MoveGroup "" ""
							"Delete Group" group gorilla::DeleteGroup "" ""
							}
	Security	security { "Password Policy ..." open gorilla::PasswordPolicy "" ""
							"Customize ..." open gorilla::DatabasePreferencesDialog "" ""
							separator "" "" "" ""
							"Change Master Password ..." open gorilla::ChangePassword "" ""
							separator "" "" "" ""
							"Lock now" open gorilla::LockDatabase "" ""
							}
	Help	help	{ "Help ..." "" gorilla::Help "" ""
							"License ..." "" gorilla::License "" ""
							separator mac "" "" ""
							"About ..." mac tkAboutDialog "" ""
							}
}	

	foreach {menu_name menu_widget menu_itemlist} $::gorilla::menu_desc {
		
		.mbar add cascade -label [mc $menu_name] -menu .mbar.$menu_widget
	
		menu .mbar.$menu_widget
		
		set taglist ""
		
		foreach {menu_item menu_tag menu_command meta_key shortcut} $menu_itemlist {
	
			# erstelle für jedes widget eine Tag-Liste
			lappend taglist $menu_tag
			if {$menu_tag eq "mac" && [tk windowingsystem] == "aqua"} {
				continue
			}
			if {$menu_item eq "separator"} {
				.mbar.$menu_widget add separator
			} else {
			  eval set meta_key $meta_key
				set shortcut [join "$meta_key $shortcut" +]
				.mbar.$menu_widget add command -label [mc $menu_item] \
					-command $menu_command -accelerator $shortcut
			} 	
			set ::gorilla::tag_list($menu_widget) $taglist
		} 
	}

# menueintrag deaktivieren mit dem tag "login
# suche in menu_tag(widget) in den Listen dort nach dem Tag "open" mit lsearch -all
# etwa in $menu_tag(file) = {"" login}, ergibt index=2
# Zuständige Prozedur: setmenustate .mbar login disabled/normal
# Index des Menueintrags finden:

# suche alle Einträge mit dem Tag tag und finde den Index
 # .mbar.file entryconfigure 2 -state disabled
 
	wm title . "Password Gorilla"
	wm iconname . "Gorilla"
	wm iconphoto . $::gorilla::images(application) 
	
	if {[info exists ::gorilla::preference(geometry,.)]} {
		TryResizeFromPreference .
	 } else {
		wm geometry . 640x480
	 }

	#---------------------------------------------------------------------
	# Arbeitsfläche bereitstellen unter Verwendung von ttk::treeview
	# Code aus ActiveTcl demo/tree.tcl
	#---------------------------------------------------------------------
	
	set tree [ttk::treeview .tree \
		-yscroll ".vsb set" -xscroll ".hsb set" -show tree \
		-style gorilla.Treeview]
	.tree tag configure red -foreground red
	.tree tag configure black -foreground black

	if {[tk windowingsystem] ne "aqua"} {
			ttk::scrollbar .vsb -orient vertical -command ".tree yview"
			ttk::scrollbar .hsb -orient horizontal -command ".tree xview"
	} else {
			scrollbar .vsb -orient vertical -command ".tree yview"
			scrollbar .hsb -orient horizontal -command ".tree xview"
	}
	ttk::label .status -relief sunken -padding [list 5 2]
	pack .status -side bottom -fill x

	## Arrange the tree and its scrollbars in the toplevel
	lower [ttk::frame .dummy]
	pack .dummy -fill both -fill both -expand 1
	grid .tree .vsb -sticky nsew -in .dummy
	grid columnconfigure .dummy 0 -weight 1
	grid rowconfigure .dummy 0 -weight 1
	
	bind .tree <Double-Button-1> {gorilla::TreeNodeDouble [.tree focus]}
	bind $tree <Button-3> {gorilla::TreeNodePopup [gorilla::GetSelectedNode]}
	bind .tree <<TreeviewSelect>> gorilla::TreeNodeSelectionChanged
	
		# On the Macintosh, make the context menu also pop up on
		# Control-Left Mousebutton and button 2 <right-click>
		
		catch {
			if {[tk windowingsystem] == "aqua"} {
					bind .tree <$meta-Button-1> {gorilla::TreeNodePopup [gorilla::GetSelectedNode]}
					bind .tree <Button-2> {gorilla::TreeNodePopup [gorilla::GetSelectedNode]}
			}
		}
		
		#
		# remember widgets
		#

		set ::gorilla::toplevel(.) "."
		set ::gorilla::widgets(main) ".mbar"
		set ::gorilla::widgets(tree) ".tree"
		
		#
		# Initialize menu state
		#

		UpdateMenu
		# setmenustate .mbar group disabled
		# setmenustate .mbar login disabled
		
		#
		# bindings
		#

		catch {bind . <MouseWheel> "$tree yview scroll \[expr {-%D/120}\] units"}

		bind . <$meta-o> {.mbar.file invoke 1}
		bind . <$meta-s> {.mbar.file invoke 3}
		bind . <$meta-x> {.mbar.file invoke 10}
		
		bind . <$meta-u> {.mbar.edit invoke 0}
		bind . <$meta-p> {.mbar.edit invoke 1}
		bind . <$meta-w> {.mbar.edit invoke 2}
		bind . <$meta-c> {.mbar.edit invoke 4}
		bind . <$meta-f> {.mbar.edit invoke 6}
		bind . <$meta-g> {.mbar.edit invoke 7}

		bind . <$meta-a> {.mbar.login invoke 0}
		bind . <$meta-e> {.mbar.login invoke 1}
		bind . <$meta-v> {.mbar.login invoke 2}
		
		# bind . <$meta-L> "gorilla::Reload"
		# bind . <$meta-R> "gorilla::Refresh"
		# bind . <$meta-C> "gorilla::ToggleConsole"
		# bind . <$meta-q> "gorilla::Exit"
		# bind . <$meta-q> "gorilla::msg"
		# ctrl-x ist auch exit, ctrl-q reicht

		#
		# Handler for the X Selection
		#

		selection handle . gorilla::XSelectionHandler

		#
		# Handler for the WM_DELETE_WINDOW event, which is sent when the
		# user asks the window manager to destroy the application
		#

		wm protocol . WM_DELETE_WINDOW gorilla::Exit


}

#
# Initialize the Pseudo Random Number Generator
#

proc gorilla::InitPRNG {{seed ""}} {
		#
		# Try to compose a not very predictable seed
		#

		append seed "20041201"
		append seed [clock seconds] [clock clicks] [pid]
		append seed [winfo id .] [winfo geometry .] [winfo pointerxy .]
		set hashseed [pwsafe::int::sha1isz $seed]

		#
		# Init PRNG
		#

		isaac::srand $hashseed
		set ::gorilla::isPRNGInitialized 1
}

proc setmenustate {widget tag_pattern state} {
	if {$tag_pattern eq "all"} {
		foreach {menu_name menu_widget menu_itemlist} $::gorilla::menu_desc {
			set index 0
			foreach {title a b c d } $menu_itemlist {
				if { $title ne "separator" } {
					$widget.$menu_widget entryconfigure $index -state $state
				}
				incr index
			}
		}
		return
	}
	foreach {menu_name menu_widget menu_itemlist} $::gorilla::menu_desc {
		set result [lsearch -all $::gorilla::tag_list($menu_widget) $tag_pattern]
		foreach index $result {
			$widget.$menu_widget entryconfigure $index -state $state
		}	
	}
}

proc gorilla::EvalIfStateNormal {menuentry index} {
	if {[$menuentry entrycget $index -state] == "normal"} {
		eval [$menuentry entrycget 0 -command]
	}
}

# ----------------------------------------------------------------------
# Tree Management: Select a node
# ----------------------------------------------------------------------
#

proc gorilla::GetSelectedNode { } {
	# returns node at mouse position
	set xpos [winfo pointerx .]
	set ypos [winfo pointery .]
	set rootx [winfo rootx .]
	set rooty [winfo rooty .]

	set relx [incr xpos -$rootx]
	set rely [incr ypos -$rooty]

	return [.tree identify row $relx $rely]
}

proc gorilla::TreeNodeSelect {node} {
	ArrangeIdleTimeout
	set selection [$::gorilla::widgets(tree) selection]

	if {[llength $selection] > 0} {
		set currentselnode [lindex $selection 0]

		if {$node == $currentselnode} {
			return
		}
	}

	focus $::gorilla::widgets(tree)
	$::gorilla::widgets(tree) selection set $node
	$::gorilla::widgets(tree) see $node
	set ::gorilla::activeSelection 0
}

# proc gorilla::TreeNodeSelectionChanged {widget nodes} {
proc gorilla::TreeNodeSelectionChanged {} {
		UpdateMenu
		ArrangeIdleTimeout
}

#
# ----------------------------------------------------------------------
# Tree Management: Double click
# ----------------------------------------------------------------------
#
# Double click on a group toggles its openness
#; already implemented in ttk::treeview
# Double click on a login copies the password to the clipboard; implemented
#

proc gorilla::TreeNodeDouble {node} {
	ArrangeIdleTimeout
	focus $::gorilla::widgets(tree)
	$::gorilla::widgets(tree) see $node

	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]

	if {$type == "Group" || $type == "Root"} {
		# set open [$::gorilla::widgets(tree) itemcget $node -open]
		# if {$open} {
				# $::gorilla::widgets(tree) itemconfigure $node -open 0
		# } else {
				# $::gorilla::widgets(tree) itemconfigure $node -open 1
		# }
		return
	} else {
		if {[info exists ::gorilla::preference(doubleClickAction)]} {
				switch -- $::gorilla::preference(doubleClickAction) {
					copyPassword {
						gorilla::CopyPassword
					}
					editLogin {
						gorilla::EditLogin
					}
				default {
					# do nothing
				}
			}
		}
	}
}

#
# ----------------------------------------------------------------------
# Tree Management: Popup
# ----------------------------------------------------------------------
#

proc gorilla::TreeNodePopup {node} {
	ArrangeIdleTimeout
	TreeNodeSelect $node

	set xpos [expr [winfo pointerx .] + 5]
	set ypos [expr [winfo pointery .] + 5]

	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]

	switch -- $type {
		Root -
		Group {
			GroupPopup $node $xpos $ypos
		}
		Login {
			LoginPopup $node $xpos $ypos
		}
	}
}

# ----------------------------------------------------------------------
# Tree Management: Popup for a Group
# ----------------------------------------------------------------------
#

proc gorilla::GroupPopup {node xpos ypos} {
		if {![info exists ::gorilla::widgets(popup,Group)]} {
	set ::gorilla::widgets(popup,Group) [menu .popupForGroup]
	$::gorilla::widgets(popup,Group) add command \
		-label [mc "Add Login"] \
		-command "gorilla::PopupAddLogin"
	$::gorilla::widgets(popup,Group) add command \
		-label [mc "Add Subgroup"] \
		-command "gorilla::PopupAddSubgroup"
	$::gorilla::widgets(popup,Group) add command \
		-label [mc "Rename Group"] \
		-command "gorilla::PopupRenameGroup"
	$::gorilla::widgets(popup,Group) add separator
	$::gorilla::widgets(popup,Group) add command \
		-label [mc "Delete Group"] \
		-command "gorilla::PopupDeleteGroup"
		}

		set data [$::gorilla::widgets(tree) item $node -values]
		set type [lindex $data 0]

		if {$type == "Root"} {
	$::gorilla::widgets(popup,Group) entryconfigure 2 -state disabled
	$::gorilla::widgets(popup,Group) entryconfigure 4 -state disabled
		} else {
	$::gorilla::widgets(popup,Group) entryconfigure 2 -state normal
	$::gorilla::widgets(popup,Group) entryconfigure 4 -state normal
		}

		tk_popup $::gorilla::widgets(popup,Group) $xpos $ypos
}

proc gorilla::PopupAddLogin {} {
		set node [lindex [$::gorilla::widgets(tree) selection] 0]
		set data [$::gorilla::widgets(tree) item $node -values]
		set type [lindex $data 0]

		if {$type == "Group"} {
	gorilla::AddLoginToGroup [lindex $data 1]
		} elseif {$type == "Root"} {
	gorilla::AddLoginToGroup ""
		}
}

proc gorilla::PopupAddSubgroup {} {
		gorilla::AddSubgroup
}

proc gorilla::PopupDeleteGroup {} {
		gorilla::DeleteGroup
}

proc gorilla::PopupRenameGroup {} {
		gorilla::RenameGroup
}


# ----------------------------------------------------------------------
# Tree Management: Popup for a Login
# ----------------------------------------------------------------------
#

proc gorilla::LoginPopup {node xpos ypos} {
		if {![info exists ::gorilla::widgets(popup,Login)]} {
	set ::gorilla::widgets(popup,Login) [menu .popupForLogin]
	$::gorilla::widgets(popup,Login) add command \
		-label [mc "Copy Username to Clipboard"] \
		-command "gorilla::PopupCopyUsername"
	$::gorilla::widgets(popup,Login) add command \
		-label [mc "Copy Password to Clipboard"] \
		-command "gorilla::PopupCopyPassword"
	$::gorilla::widgets(popup,Login) add command \
		-label [mc "Copy URL to Clipboard"] \
		-command "gorilla::PopupCopyURL"
	$::gorilla::widgets(popup,Login) add separator
	$::gorilla::widgets(popup,Login) add command \
		-label [mc "Edit Login"] \
		-command "gorilla::PopupEditLogin"
	$::gorilla::widgets(popup,Login) add command \
		-label [mc "View Login"] \
		-command "gorilla::PopupViewLogin"
	$::gorilla::widgets(popup,Login) add separator 
	$::gorilla::widgets(popup,Login) add command \
		-label [mc "Delete Login"] \
		-command "gorilla::PopupDeleteLogin"
		}

		tk_popup $::gorilla::widgets(popup,Login) $xpos $ypos
}

proc gorilla::PopupEditLogin {} {
		gorilla::EditLogin
}

proc gorilla::PopupViewLogin {} {
	gorilla::ViewLogin
}

proc gorilla::PopupCopyUsername {} {
		gorilla::CopyUsername
}

proc gorilla::PopupCopyPassword {} {
		gorilla::CopyPassword
}

proc gorilla::PopupCopyURL {} {
		gorilla::CopyURL
}

proc gorilla::PopupDeleteLogin {} {
		DeleteLogin
}


# ----------------------------------------------------------------------
# New
# ----------------------------------------------------------------------
#

#
# Attempt to resize a toplevel window based on our preference
#

proc gorilla::TryResizeFromPreference {top} {
	if {![info exists ::gorilla::preference(rememberGeometries)] || \
			!$::gorilla::preference(rememberGeometries)} {
		return
	}
	if {![info exists ::gorilla::preference(geometry,$top)]} {
		return
	}
	if {[scan $::gorilla::preference(geometry,$top) "%dx%d" width height] != 2} {
		unset ::gorilla::preference(geometry,$top)
		return
	}
	if {$width < 10 || $width > [winfo screenwidth .] || \
		$height < 10 || $height > [winfo screenheight .]} {
		unset ::gorilla::preference(geometry,$top)
		return
	}
	wm geometry $top ${width}x${height}
}

proc gorilla::CollectTicks {} {
	lappend ::gorilla::collectedTicks [clock clicks]
}

proc gorilla::New {} {
		ArrangeIdleTimeout

		#
		# If the current database was modified, give user a chance to think
		#

	if {$::gorilla::dirty} {
		set answer [tk_messageBox -parent . \
		-type yesnocancel -icon warning -default yes \
		-title [ mc "Save changes?" ] \
		-message [ mc "The current password database is modified.\
		Do you want to save the current database before creating\
		the new database?"]]

		# switch $answer {}
		# yes {}
		# no {aktuelle Datenbank schließen, Variable neu initialisieren}
		# default {return}
		
		if {$answer == "yes"} {
			if {[info exists ::gorilla::fileName]} {
				if {![::gorilla::Save]} {
					return
				}
			} else {
				if {![::gorilla::SaveAs]} {
					return
				}
			}
		} elseif {$answer != "no"} {
			return
		}
	}

		#
		# Timing between clicks is used for our initial random seed
		#

	set ::gorilla::collectedTicks [list [clock clicks]]
	gorilla::InitPRNG [join $::gorilla::collectedTicks -] ;# not a very good seed yet

	if { [catch {set password [GetPassword 1 [mc "New Database: Choose Master Password"]]} \
		error] } {
		# canceled
		return
	}

	lappend ::gorilla::collectedTicks [clock clicks]
	gorilla::InitPRNG [join $::gorilla::collectedTicks -] ;# much better seed now

	set myOldCursor [. cget -cursor]
	. configure -cursor watch
	update idletasks

	wm title . [mc "Password Gorilla - <New Database>"]

	# Aufräumarbeiten
	if {[info exists ::gorilla::db]} {
		itcl::delete object $::gorilla::db
	}
	set ::gorilla::dirty 0

	# create an pwsafe object ::gorilla::db 
	# with accessible by methods like: GetPreference <name>
	set ::gorilla::db [namespace current]::[pwsafe::db \#auto $password]
	pwsafe::int::randomizeVar password
	catch {unset ::gorilla::fileName}

		#
		# Apply defaults: auto-save, idle timeout, version, Unicode support
		#

	if {[info exists ::gorilla::preference(saveImmediatelyDefault)]} {
		$::gorilla::db setPreference SaveImmediately \
		$::gorilla::preference(saveImmediatelyDefault)
	}

	if {[info exists ::gorilla::preference(idleTimeoutDefault)]} {
		if {$::gorilla::preference(idleTimeoutDefault) > 0} {
			$::gorilla::db setPreference LockOnIdleTimeout 1
			$::gorilla::db setPreference IdleTimeout \
			$::gorilla::preference(idleTimeoutDefault)
		} else {
			$::gorilla::db setPreference LockOnIdleTimeout 0
		}
	}

	if {[info exists ::gorilla::preference(defaultVersion)]} {
		if {$::gorilla::preference(defaultVersion) == 3} {
			$::gorilla::db setHeaderField 0 [list 3 0]
		}
	}

	if {[info exists ::gorilla::preference(unicodeSupport)]} {
		$::gorilla::db setPreference IsUTF8 \
		$::gorilla::preference(unicodeSupport)
	}

	$::gorilla::widgets(tree) selection set {}		
	# pathname delete itemList ;# Baum löschen
	catch {	$::gorilla::widgets(tree) delete [$::gorilla::widgets(tree) children {}] }
	# catch {	$::gorilla::widgets(tree) delete [$::gorilla::widgets(tree) nodes root] }
	
# ttk:treeview: pathname insert 	parent index ?-id id? options... 
# BWidget: pathName insert				index	parent	node	?option value...? 

	$::gorilla::widgets(tree) insert {} end -id "RootNode" \
			-open true \
			-text [mc "<New Database>"]\
			-values [list Root] \
			-image $::gorilla::images(group) 
	set ::gorilla::status [mc "Add logins using \"Add Login\" in the \"Login\" menu."]
	. configure -cursor $myOldCursor

	if {[$::gorilla::db getPreference "SaveImmediately"]} {
		gorilla::SaveAs
	}
	UpdateMenu
}

# ----------------------------------------------------------------------
# Open a database file; used by "Open" and "Merge"
# ----------------------------------------------------------------------
#

proc gorilla::DestroyOpenDatabaseDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::OpenPercentTrace {name1 name2 op} {

	if {![info exists ::gorilla::openPercentLastUpdate]} {
		set ::gorilla::openPercentLastUpdate [clock clicks -milliseconds]
		return
	}
	set now [clock clicks -milliseconds]
	set td [expr {$now - $::gorilla::openPercentLastUpdate}]
	# time difference
	if {$td < 200} {
		return
	}

	set ::gorilla::openPercentLastUpdate $now

	if {$::gorilla::openPercent > 0} {
		set info [format "Opening ... %2.0f %%" $::gorilla::openPercent]
		$::gorilla::openPercentWidget configure -text $info
		update idletasks
	}
}

;# proc gorilla::OpenDatabase {title defaultFile} {}
	
# proc gorilla::OpenDatabase {title {defaultFile ""}} {
proc gorilla::OpenDatabase {title {defaultFile ""} {allowNew 0}} {
	
	ArrangeIdleTimeout
	set top .openDialog

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		
		# TryResizeFromPreference $top

		set aframe [ttk::frame $top.right -padding [list 10 5]]
		
		if {$::gorilla::preference(gorillaIcon)} {
			# label $top.splash -bg "#ffffff" -image $::gorilla::images(splash)
			ttk::label $top.splash -image $::gorilla::images(splash)
			pack $top.splash -side left -fill both -padx 10 -pady 10
		}
		
		ttk::label $aframe.info -anchor w -width 80 -relief sunken \
			 -padding [list 5 5 5 5]
		# -background #F6F69E ;# helles Gelb

		ttk::labelframe $aframe.file -text [mc "Database:"] -width 70

		ttk::combobox $aframe.file.cb -width 40
		ttk::button $aframe.file.sel -image $::gorilla::images(browse) \
			-command "set ::gorilla::guimutex 3"

		pack $aframe.file.cb -side left -padx 10 -pady 10 -fill x -expand yes
		pack $aframe.file.sel -side right -padx 10 

		ttk::labelframe $aframe.pw -text [mc "Password:"] -width 40
		ttk::entry $aframe.pw.pw -width 40 -show "*"
		bind $aframe.pw.pw <KeyPress> "+::gorilla::CollectTicks"
		bind $aframe.pw.pw <KeyRelease> "+::gorilla::CollectTicks"
		
		pack $aframe.pw.pw -side left -padx 10 -pady 10 -fill x -expand yes

		ttk::frame $aframe.buts
		set but1 [ttk::button $aframe.buts.b1 -width 9 -text "OK" \
			-command "set ::gorilla::guimutex 1"]
		set but2 [ttk::button $aframe.buts.b2 -width 9 -text [mc "Exit"] \
			-command "set ::gorilla::guimutex 2"]
		set but3 [ttk::button $aframe.buts.b3 -width 9 -text [mc "New"] \
			-command "set ::gorilla::guimutex 4"]
		pack $but1 $but2 $but3 -side left -pady 10 -padx 5 -expand 1
	
		set sep [ttk::separator $aframe.sep -orient horizontal]
		
		grid $aframe.file -row 0 -column 0 -columnspan 2 -sticky we
		grid $aframe.pw $aframe.buts -pady 10
		grid $sep -sticky we -columnspan 2 -pady 5
		grid $aframe.info -row 3 -column 0 -columnspan 2 -pady 5 -sticky we 
		grid configure $aframe.pw  -sticky w
		grid configure $aframe.buts  -sticky nse
		
		bind $aframe.file.cb <Return> "set ::gorilla::guimutex 1"
		bind $aframe.pw.pw <Return> "set ::gorilla::guimutex 1"
		bind $aframe.buts.b1 <Return> "set ::gorilla::guimutex 1"
		bind $aframe.buts.b2 <Return> "set ::gorilla::guimutex 2"
		bind $aframe.buts.b3 <Return> "set ::gorilla::guimutex 4"
		pack $aframe -side right -fill both -expand yes

		pack $aframe -expand 1
		
		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyOpenDatabaseDialog

		} else {
			set aframe $top.right
			wm deiconify $top
		}

	wm title $top $title
	$aframe.pw.pw delete 0 end

	if {[info exists ::gorilla::preference(lru)] \
			&& [llength $::gorilla::preference(lru)] } {
		$aframe.file.cb configure -values $::gorilla::preference(lru)
		$aframe.file.cb current 0
	}

	if {$allowNew} {
		set info [mc "Select a database, and enter its password. Click \"New\" to create a new database."]
		$aframe.buts.b3 configure -state normal
	} else {
		set info "Select a database, and enter its password."
		$aframe.buts.b3 configure -state disabled
	}

		$aframe.info configure -text $info

		if {$defaultFile != ""} {
			catch {set ::gorilla::dirName [file dirname $defaultFile]}

			set values [$aframe.file.cb get]
			set found [lsearch -exact $values $defaultFile]

			if {$found != -1} {
				$aframe.file.cb current $found
			} else {
				set values [linsert $values 0 $defaultFile]
				$aframe.file.cb configure -values $values
				$aframe.file.cb current 0
			}
		}


		#
    # Disable the main menu, so that it is not accessible, even on the Mac.
    #
    
    setmenustate $::gorilla::widgets(main) all disabled

    #
		# Run dialog
		#

		set oldGrab [grab current .]

		update idletasks
		raise $top
		focus $aframe.pw.pw
		if {[tk windowingsystem] != "aqua"} {
			catch {grab $top}
		}

		#
		# Timing between clicks is used for our initial random seed
		#

		set ::gorilla::collectedTicks [list [clock clicks]]
		gorilla::InitPRNG [join $::gorilla::collectedTicks -] ;# not a very good seed yet

		while {42} {
	ArrangeIdleTimeout
	set ::gorilla::guimutex 0
	vwait ::gorilla::guimutex

	lappend myClicks [clock clicks]

	if {$::gorilla::guimutex == 2} {
    # Cancel
    break
	} elseif {$::gorilla::guimutex == 4} {
    # New
		break
	} elseif {$::gorilla::guimutex == 1} {
			set fileName [$aframe.file.cb get]
			set nativeName [file nativename $fileName]

		if {$fileName == ""} {
			tk_messageBox -parent $top -type ok -icon error -default ok \
				-title "No File" \
				-message "Please select a password database."
			continue
		}

		if {![file readable $fileName]} {
			tk_messageBox -parent $top -type ok -icon error -default ok \
				-title "File Not Found" \
				-message "The password database\
				\"$nativeName\" does not exist or can not\
				be read."
			continue
		}

		$aframe.info configure -text [mc "Please be patient. Verifying password ..."]

		set myOldCursor [$top cget -cursor]
		set dotOldCursor [. cget -cursor]
		$top configure -cursor watch
		. configure -cursor watch
		update idletasks

		lappend ::gorilla::collectedTicks [clock clicks]
		gorilla::InitPRNG [join $::gorilla::collectedTicks -] ;# much better seed now

		set password [$aframe.pw.pw get]

		set ::gorilla::openPercent 0
		set ::gorilla::openPercentWidget $aframe.info
		trace add variable ::gorilla::openPercent [list "write"] \
	::gorilla::OpenPercentTrace
		if {[catch {set newdb [pwsafe::createFromFile $fileName $password \
					 ::gorilla::openPercent]} oops]} {
			pwsafe::int::randomizeVar password
			trace remove variable ::gorilla::openPercent [list "write"] \
				::gorilla::OpenPercentTrace
			unset ::gorilla::openPercent
		. configure -cursor $dotOldCursor
		$top configure -cursor $myOldCursor

		tk_messageBox -parent $top -type ok -icon error -default ok \
			-title "Error Opening Database" \
			-message "Can not open password database\
			\"$nativeName\": $oops"
		$aframe.info configure -text $info
		$aframe.pw.pw delete 0 end
		focus $aframe.pw.pw
		continue
		}
		# all seems well
		trace remove variable ::gorilla::openPercent [list "write"] \
	::gorilla::OpenPercentTrace
		unset ::gorilla::openPercent

		. configure -cursor $dotOldCursor
		$top configure -cursor $myOldCursor
		pwsafe::int::randomizeVar password
		break
	} elseif {$::gorilla::guimutex == 3} {
			set types {
				{{Password Database Files} {.psafe3 .dat}}
				{{All Files} *}
			}

			if {![info exists ::gorilla::dirName]} {
				if {[tk windowingsystem] == "aqua"} {
					set ::gorilla::dirName "~/Documents"
				} else {
				# Windows-Abfrage auch nötig ...
					set ::gorilla::dirName [pwd]
				}
			}

			set fileName [tk_getOpenFile -parent $top \
				-title "Browse for a password database ..." \
				-filetypes $types \
				-initialdir $::gorilla::dirName]
			# -defaultextension ".psafe3" 
			if {$fileName == ""} {
				continue
			}

			set nativeName [file nativename $fileName]
			catch {
				set ::gorilla::dirName [file dirname $fileName]
			}

			set values [$aframe.file.cb cget -values]
			set found [lsearch -exact $values $nativeName]

			if {$found != -1} {
				$aframe.file.cb current $found
			} else {
				set values [linsert $values 0 $nativeName]
				$aframe.file.cb configure -values $values
				$aframe.file.cb current 0
				# $aframe.file.cb setvalue @0
			}

			focus $aframe.pw.pw
	}
		} ;# end while

		set fileName [$aframe.file.cb get]
		set nativeName [file nativename $fileName]
		pwsafe::int::randomizeVar ::gorilla::collectedTicks
		$aframe.pw.pw configure -text ""
# set $aframe.pw.entry ""
		if {$oldGrab != ""} {
			catch {grab $oldGrab}
		} else {
			catch {grab release $top}
		}

		wm withdraw $top
		update

    #
    # Re-enable the main menu.
    #

    setmenustate $::gorilla::widgets(main) all normal

    if {$::gorilla::guimutex == 2} {
			# Cancel
			return "Cancel"
    } elseif {$::gorilla::guimutex == 4} {
			# New
			return "New"
		}

		#
		# Add file to LRU preference
		#

		if {[info exists ::gorilla::preference(lru)]} {
			set found [lsearch -exact $::gorilla::preference(lru) $nativeName]
			if {$found == -1} {
# not found
				set ::gorilla::preference(lru) [linsert $::gorilla::preference(lru) 0 $nativeName]
			} elseif {$found != 0} {
				set tmp [lreplace $::gorilla::preference(lru) $found $found]
				set ::gorilla::preference(lru) [linsert $tmp 0 $nativeName]
			}
		} else {
			set ::gorilla::preference(lru) [list $nativeName]
		}

		#
		# Show any warnings?
		#

		set dbWarnings [$newdb cget -warningsDuringOpen]

		if {[llength $dbWarnings] > 0} {
	set message $fileName
	append message ": " [join $dbWarnings "\n"]
	tk_messageBox -parent . \
			-type ok -icon warning -title "File Warning" \
			-message $message
		}

		#
		# All seems well
		#

		ArrangeIdleTimeout
		return [list "Open" $fileName $newdb]
}

#
# ----------------------------------------------------------------------
# Open a file
# ----------------------------------------------------------------------
#

# Open erhält eine Liste, die kann auch leer sein...

proc gorilla::Open {{defaultFile ""}} {

		#
		# If the current database was modified, give user a chance to think
		#
	if {$::gorilla::dirty} {
		set answer [tk_messageBox -parent . \
			-type yesnocancel -icon warning -default yes \
			-title "Save changes?" \
			-message "The current password database is modified.\
			Do you want to save the database?\n\
			\"Yes\" saves the database, and continues to the \"Open File\" dialog.\n\
			\"No\" discards all changes, and continues to the \"Open File\" dialog.\n\
			\"Cancel\" returns to the main menu."]
		if {$answer == "yes"} {
			if {[info exists ::gorilla::fileName]} {
				if {![::gorilla::Save]} {
					return
				}
			} else {
				if {![::gorilla::SaveAs]} {
					return
				}
			}
		} elseif {$answer != "no"} {
			return
		}
	}

	set openInfo [OpenDatabase [mc "Open Password Database"] $defaultFile 1]
	
	set action [lindex $openInfo 0]

	if {$action == "Cancel"} {
		return "Cancel"
	} elseif {$action == "New"} {
		gorilla::New
		return "New"
	}

  set fileName [lindex $openInfo 1]
	set newdb [lindex $openInfo 2]
	set nativeName [file nativename $fileName]

	wm title . "Password Gorilla - $nativeName"

	if {[info exists ::gorilla::db]} {
		itcl::delete object $::gorilla::db
	}

	set ::gorilla::status [mc "Password database $nativeName loaded."]
	set ::gorilla::fileName $fileName
	set ::gorilla::db $newdb
	set ::gorilla::dirty 0

	$::gorilla::widgets(tree) selection set ""
	# delete all the tree
	# $::gorilla::widgets(tree) delete [$::gorilla::widgets(tree) nodes root]
	$::gorilla::widgets(tree) delete [$::gorilla::widgets(tree) children {}]
	
	
	catch {array unset ::gorilla::groupNodes}

	$::gorilla::widgets(tree) insert {} end -id "RootNode" \
		-open 1 \
		-image $::gorilla::images(group) \
		-text $nativeName \
		-values [list Root]

	AddAllRecordsToTree
	UpdateMenu
	return "Open"
}



# ----------------------------------------------------------------------
# Add a Login
# ----------------------------------------------------------------------


proc gorilla::AddLogin {} {
	gorilla::PopupAddLogin
	# AddLoginToGroup ""
}

# ----------------------------------------------------------------------
# Add a Login to a Group
# ----------------------------------------------------------------------

proc gorilla::AddLoginToGroup {group} {
	ArrangeIdleTimeout

	if {![info exists ::gorilla::db]} {
		tk_messageBox -parent . \
		-type ok -icon error -default ok \
		-title "No Database" \
		-message "Please create a new database, or open an existing\
		database first."
		return
	}

# r-ecord n-umber
	set rn [$::gorilla::db createRecord]

	if {$group != ""} {
		$::gorilla::db setFieldValue $rn 2 $group
	}

	if {![catch {package present uuid}]} {
		$::gorilla::db setFieldValue $rn 1 [uuid::uuid generate]
	}

	$::gorilla::db setFieldValue $rn 7 [clock seconds]

	set res [LoginDialog $rn]
	if {$res == 0} {
		# canceled
		$::gorilla::db deleteRecord $rn
		set ::gorilla::status [mc "Addition of new login canceled."]
		return
	}

	set ::gorilla::status [mc "New login added."]
	AddRecordToTree $rn
	MarkDatabaseAsDirty
}

# ----------------------------------------------------------------------
# Edit a Login
# ----------------------------------------------------------------------
#

proc gorilla::EditLogin {} {
	ArrangeIdleTimeout

	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		return
	 }
	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]

	if {$type == "Group" || $type == "Root"} {
		return
	}

	set rn [lindex $data 1]

	if {[$::gorilla::db existsField $rn 2]} {
		set oldGroupName [$::gorilla::db getFieldValue $rn 2]
	} else {
		set oldGroupName ""
	}

	set res [LoginDialog $rn]

	if {$res == 0} {
		set ::gorilla::status [mc "Login unchanged."]
		# canceled
		return
	}

	if {[$::gorilla::db existsField $rn 2]} {
		set newGroupName [$::gorilla::db getFieldValue $rn 2]
	} else {
		set newGroupName ""
	}

	if {$oldGroupName != $newGroupName} {
		$::gorilla::widgets(tree) delete $node
		AddRecordToTree $rn
	} else {
		if {[$::gorilla::db existsField $rn 3]} {
			set title [$::gorilla::db getFieldValue $rn 3]
		} else {
			set title ""
		}

		if {[$::gorilla::db existsField $rn 4]} {
			append title " \[" [$::gorilla::db getFieldValue $rn 4] "\]"
		}

		$::gorilla::widgets(tree) item $node -text $title
	}

	set ::gorilla::status [mc "Login modified."]
	MarkDatabaseAsDirty
}

# ----------------------------------------------------------------------
# Move a Login
# ----------------------------------------------------------------------
#

proc gorilla::MoveLogin {} {
	gorilla::MoveDialog Login
}

proc gorilla::MoveGroup {} {
	gorilla::MoveDialog Group
}

proc gorilla::MoveDialog {type} {
	ArrangeIdleTimeout
	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		return
	}
	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set nodetype [lindex $data 0]

	set top .moveDialog
	
	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		TryResizeFromPreference $top
		wm title $top [mc "Move $type"]

		ttk::labelframe $top.source -text [mc $type] -padding [list 10 10]
		ttk::entry $top.source.e -width 40 -textvariable ::gorilla::MoveDialogSource
		ttk::labelframe $top.dest \
		-text [mc "Destination Group with format <Group.Subgroup> :"] \
		-padding [list 10 10]
		ttk::entry $top.dest.e -width 40 -textvariable ::gorilla::MoveDialogDest
		# Format: group.subgroup
		pack $top.source.e -side left -expand yes -fill x
		pack $top.source -side top -expand yes -fill x -pady 10 -padx 10
		pack $top.dest.e -side left -expand yes -fill x
		pack $top.dest -side top -expand yes -fill x -fill y -pady 10 -padx 10

		ttk::frame $top.buts
		set but1 [ttk::button $top.buts.b1 -width 10 -text "OK" \
		 -command "set ::gorilla::guimutex 1"]
		set but2 [ttk::button $top.buts.b2 -width 10 -text [mc "Cancel"] \
			 -command "set ::gorilla::guimutex 2"]
		pack $but1 $but2 -side left -pady 10 -padx 20
		pack $top.buts -side bottom -pady 10 -fill y -expand yes
	
		bind $top.source.e <Shift-Tab> "after 0 \"focus $top.buts.b1\""
		bind $top.dest.e <Shift-Tab> "after 0 \"focus $top.source.e\""
		
		bind $top.source.e <Return> "set ::gorilla::guimutex 1"
		bind $top.dest.e <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b1 <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b2 <Return> "set ::gorilla::guimutex 2"

		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyAddSubgroupDialog
	} else {
		wm deiconify $top
	}
	
	# Configure Dialog

	if {$nodetype == "Group"} {
		set ::gorilla::MoveDialogSource [lindex $data 1]		
	} elseif {$nodetype == "Login"} {
		set rn [lindex $data 1]
		if {[$::gorilla::db existsField $rn 3]} {
			set ::gorilla::MoveDialogSource [$::gorilla::db getFieldValue $rn 3]
		}
	} else {
		return
	}
	set ::gorilla::MoveDialogDest ""

	# Run Dialog

	set oldGrab [grab current .]

	update idletasks
	raise $top
	focus $top.dest.e
	catch {grab $top}
	
	while {42} {
		ArrangeIdleTimeout
		set ::gorilla::guimutex 0
		vwait ::gorilla::guimutex

		set sourceNode [$top.source.e get]
		set destGroup [$top.dest.e get]

		if {$::gorilla::guimutex != 1} {
				break
		}
		#
		# The group name must not be empty
		# 
		
		if {$destGroup == ""} {
				tk_messageBox -parent $top \
					-type ok -icon error -default ok \
					-title "Invalid Group Name" \
					-message "The group name can not be empty."
				continue
		}

		#
		# See if the destination's group name can be parsed
		#

		if {[catch {
				set destNode $::gorilla::groupNodes($destGroup)
		}]} {
			tk_messageBox -parent $top \
				-type ok -icon error -default ok \
				-title "Invalid Group Name" \
				-message "The name of the parent group is invalid."
			continue
		}
		# all seems well
		break
	}

	if {$oldGrab != ""} {
		catch {grab $oldGrab}
	} else {
		catch {grab release $top}
	}

	wm withdraw $top

	if {$::gorilla::guimutex != 1} {
		set ::gorilla::status [mc "Moving of $type canceled."]
		return
	}

	gorilla::MoveTreeNode $node $destNode
	
	$::gorilla::widgets(tree) item $destNode -open 1
	$::gorilla::widgets(tree) item "RootNode" -open 1
	set ::gorilla::status [mc "$type moved."]
	MarkDatabaseAsDirty
}


# ----------------------------------------------------------------------
# Delete a Login
# ----------------------------------------------------------------------
#

proc gorilla::DeleteLogin {} {
	ArrangeIdleTimeout

	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		return
	}

	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]
	set rn [lindex $data 1]

	if {$type != "Login"} {
		error "oops"
	}
	
	# It is good if there is necessarily a question, no if-question necessary
	if {0} {
		set answer [tk_messageBox -parent . \
			-type yesno -icon question -default no \
			-title [mc "Delete Login"] \
			-message [mc "Are you sure that you want to delete this login?"]]

		if {$answer != "yes"} {
			return
		}
	}

	$::gorilla::db deleteRecord $rn
	$::gorilla::widgets(tree) delete $node
	set ::gorilla::status [mc "Login deleted."]
	MarkDatabaseAsDirty
}

# ----------------------------------------------------------------------
# Add a new group
# ----------------------------------------------------------------------
#

proc gorilla::AddGroup {} {
	gorilla::AddSubgroup
	# gorilla::AddSubgroupToGroup ""
}

#
# ----------------------------------------------------------------------
# Add a new subgroup (to the selected group)
# ----------------------------------------------------------------------
#

proc gorilla::AddSubgroup {} {
	set sel [$::gorilla::widgets(tree) selection]

	if {[llength $sel] == 0} {
		
		# No selection. Add to toplevel
		#
		gorilla::AddSubgroupToGroup ""
		
	} else {
		set node [lindex $sel 0]
		set data [$::gorilla::widgets(tree) item $node -values]
		set type [lindex $data 0]

		if {$type == "Group"} {
			gorilla::AddSubgroupToGroup [lindex $data 1]
		} elseif {$type == "Root"} {
			gorilla::AddSubgroupToGroup ""
		} else {
			
			# A login is selected. Add to its parent group.
			#
			set parent [$::gorilla::widgets(tree) parent $node]
			if {[string equal $parent "RootNode"]} {
				gorilla::AddSubgroupToGroup ""
			} else {
				set pdata [$::gorilla::widgets(tree) item $node -values]
				gorilla::AddSubgroupToGroup [lindex $pdata 1]
			}
		}
	}
}

#
# ----------------------------------------------------------------------
# Add a new subgroup
# ----------------------------------------------------------------------
#

proc gorilla::DestroyAddSubgroupDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::AddSubgroupToGroup {parentName} {
	ArrangeIdleTimeout

	if {![info exists ::gorilla::db]} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "No Database" \
			-message "Please create a new database, or open an existing\
			database first."
		return
	}

	set top .subgroupDialog

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		TryResizeFromPreference $top
		wm title $top [mc "Add a new Group"]

		ttk::labelframe $top.parent -text [mc "Parent:"] \
		 -padding [list 10 10]
		ttk::entry $top.parent.e -width 40 -textvariable ::gorilla::subgroup.parent
		pack $top.parent.e -side left -expand yes -fill x
		pack $top.parent -side top -expand yes -fill x -pady 10 -padx 10

		ttk::labelframe $top.group -text [mc "New Group Name:"] -padding [list 10 10]
		ttk::entry $top.group.e -width 40 -textvariable ::gorilla::subgroup.group
		
		pack $top.group.e -side left -expand yes -fill x
		pack $top.group -side top -expand yes -fill x -pady 10 -padx 10

		ttk::frame $top.buts
		set but1 [ttk::button $top.buts.b1 -width 10 -text "OK" \
			-command "set ::gorilla::guimutex 1"]
		set but2 [ttk::button $top.buts.b2 -width 10 -text [mc "Cancel"] \
			-command "set ::gorilla::guimutex 2"]
		pack $but1 $but2 -side left -pady 10 -padx 20
		pack $top.buts -side bottom -pady 10
	
		bind $top.parent.e <Shift-Tab> "after 0 \"focus $top.buts.b1\""
		bind $top.group.e <Shift-Tab> "after 0 \"focus $top.parent.e\""
		
		bind $top.parent.e <Return> "set ::gorilla::guimutex 1"
		bind $top.group.e <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b1 <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b2 <Return> "set ::gorilla::guimutex 2"

		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyAddSubgroupDialog
	} else {
		wm deiconify $top
	}

	# $top.parent configure -text $parentName
	# $top.group configure -text ""
	set ::gorilla::subgroup.parent $parentName
	set ::gorilla::subgroup.group ""

	set oldGrab [grab current .]

	update idletasks
	raise $top
	focus $top.group.e
	catch {grab $top}

	while {42} {
		ArrangeIdleTimeout
		set ::gorilla::guimutex 0
		vwait ::gorilla::guimutex

		set parent [$top.parent.e get]
		set group [$top.group.e get]

		if {$::gorilla::guimutex != 1} {
				break
		}
		#
		# The group name must not be empty
		#

		if {$group == ""} {
				tk_messageBox -parent $top \
					-type ok -icon error -default ok \
					-title "Invalid Group Name" \
					-message "The group name can not be empty."
				continue
		}

		#
		# See if the parent's group name can be parsed
		#

		if {[catch {
				set parents [pwsafe::db::splitGroup $parent]
		}]} {
			tk_messageBox -parent $top \
				-type ok -icon error -default ok \
				-title "Invalid Group Name" \
				-message "The name of the parent group is invalid."
			continue
		}

		break
	}

	if {$oldGrab != ""} {
		catch { grab $oldGrab }
	} else {
		catch { grab release $top }
	}

	wm withdraw $top

	if {$::gorilla::guimutex != 1} {
		set ::gorilla::status [mc "Addition of group canceled."]
		return
	}

	lappend parents $group
	set fullGroupName [pwsafe::db::concatGroups $parents]
	AddGroupToTree $fullGroupName

	set piter [list]
	foreach parent $parents {
		lappend piter $parent
		set fullParentName [pwsafe::db::concatGroups $piter]
		set node $::gorilla::groupNodes($fullParentName)
		$::gorilla::widgets(tree) item $node -open 1
	}

	$::gorilla::widgets(tree) item "RootNode" -open 1
	set ::gorilla::status [mc "New group added."]
	# MarkDatabaseAsDirty

}

# ----------------------------------------------------------------------
# Move Node to a new Group
# ----------------------------------------------------------------------
#

proc gorilla::MoveTreeNode {node dest} {
	set nodedata [$::gorilla::widgets(tree) item $node -values]
	set destdata [$::gorilla::widgets(tree) item $dest -values]
	set nodetype [lindex $nodedata 0]
# node6 to node3
#node7 node1
# menü move login erscheint nur, wenn ein Login angeklickt ist
# entsprechend MOVE GROUP nur, wenn tag group aktiviert ist

	if {$nodetype == "Root"} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "Root Node Can Not Be Moved" \
			-message "The root node can not be moved."
return
	}

	set desttype [lindex $destdata 0]

	if {$desttype == "RootNode"} {
		set destgroup ""
	} else {
		set destgroup [lindex $destdata 1]
	}

		#
		# Move a Login
		#

	if {$nodetype == "Login"} {
		set rn [lindex $nodedata 1]
		$::gorilla::db setFieldValue $rn 2 $destgroup
		$::gorilla::widgets(tree) delete $node
		AddRecordToTree $rn
		MarkDatabaseAsDirty
		return
	}
# bis hier
		#
		# Moving a group to its immediate parent does not have any effect
		#

	if {$dest == [$::gorilla::widgets(tree) parent $node]} {
		return
	}
	
		#
		# When we are moving a group, make sure that destination is not a
		# child of this group
		#

	set destiter $dest
	while {$destiter != "RootNode"} {
		if {$destiter == $node} {
			break
		}
		set destiter [$::gorilla::widgets(tree) parent $destiter]
	}

	if {$destiter != "RootNode" || $node == "RootNode"} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "Can Not Move Node" \
			-message "Can not move a group to a subgroup\
			of itself."
		return
	}

		#
		# Move recursively
		#

	MoveTreeNodeRek $node [pwsafe::db::splitGroup $destgroup]
	MarkDatabaseAsDirty
}

#
# Moves the children of tree node to the newParents group
#

proc gorilla::MoveTreeNodeRek {node newParents} {
	set nodedata [$::gorilla::widgets(tree) item $node -values]
	set nodename [$::gorilla::widgets(tree) item $node -text]

	lappend newParents $nodename
	set newParentName [pwsafe::db::concatGroups $newParents]
	set newParentNode [AddGroupToTree $newParentName]

	foreach child [$::gorilla::widgets(tree) children $node] {
		set childdata [$::gorilla::widgets(tree) item $child -values]
		set childtype [lindex $childdata 0]

		if {$childtype == "Login"} {
			set rn [lindex $childdata 1]
			$::gorilla::db setFieldValue $rn 2 $newParentName
			$::gorilla::widgets(tree) delete $child
			AddRecordToTree $rn
		} else {
			MoveTreeNodeRek $child $newParents
		}
	}

	set oldGroupName [lindex $nodedata 1]
	unset ::gorilla::groupNodes($oldGroupName)
	$::gorilla::widgets(tree) item $newParentNode \
		-open [$::gorilla::widgets(tree) item $node -open]
	$::gorilla::widgets(tree) delete $node
}


#
# ----------------------------------------------------------------------
# Delete Group
# ----------------------------------------------------------------------
#

proc gorilla::DeleteGroup {} {
	ArrangeIdleTimeout

	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		return
	}

	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]

	if {$type == "Root"} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "Can Not Delete Root" \
			-message "The root node can not be deleted."
		return
	}

	if {$type != "Group"} {
		error "oops"
	}

	set groupName [$::gorilla::widgets(tree) item $node -text]
	set fullGroupName [lindex $data 1]

	if {[llength [$::gorilla::widgets(tree) children $node]] > 0} {
		set answer [tk_messageBox -parent . \
			-type yesno -icon question -default no \
			-title "Delete Group" \
			-message [mc "Are you sure that you want to delete group and all its contents?"]]

		if {$answer != "yes"} {
			return
		}
		set hadchildren 1
	} else {
		set hadchildren 0
	}

	set ::gorilla::status [mc "Group deleted."]
	gorilla::DeleteGroupRek $node

	if {$hadchildren} {
		MarkDatabaseAsDirty
	}
}

proc gorilla::DeleteGroupRek {node} {
	set children [$::gorilla::widgets(tree) children $node]

	foreach child $children {
		set data [$::gorilla::widgets(tree) item $child -values]
		set type [lindex $data 0]

		if {$type == "Login"} {
			$::gorilla::db deleteRecord [lindex $data 1]
			$::gorilla::widgets(tree) delete $child
		} else {
			DeleteGroupRek $child
		}
	}

	set groupName [lindex [$::gorilla::widgets(tree) item $node -values] 1]
	unset ::gorilla::groupNodes($groupName)
	$::gorilla::widgets(tree) delete $node
}

#
# ----------------------------------------------------------------------
# Rename Group
# ----------------------------------------------------------------------
#

proc gorilla::DestroyRenameGroupDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::RenameGroup {} {
	ArrangeIdleTimeout

	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		return
	}

	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]

	if {$type == "Root"} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "Can Not Rename Root" \
			-message "The root node can not be renamed."
		return
	}

	if {$type != "Group"} {
		error "oops"
	}

	set fullGroupName [lindex $data 1]
	set groupName [$::gorilla::widgets(tree) item $node -text]
	set parentNode [$::gorilla::widgets(tree) parent $node]
	set parentData [$::gorilla::widgets(tree) item $parentNode -values]
	set parentType [lindex $parentData 0]

	if {$parentType == "Group"} {
		set parentName [lindex $parentData 1]
	} else {
		set parentName ""
	}

	set top .renameGroup

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		TryResizeFromPreference $top
		wm title $top [mc "Rename Group"]

		# set title [label $top.title -anchor center -text [mc "Rename Group"]]
		# pack $title -side top -fill x -pady 10

		# set sep1 [ttk::separator $top.sep1 -orient horizontal]
		# pack $sep1 -side top -fill x -pady 10

		ttk::labelframe $top.parent -text [mc "Parent:"] 
		ttk::entry $top.parent.e -width 40 -textvariable ::gorilla::renameGroupParent
		pack $top.parent.e -side left -expand yes -fill x -pady 5 -padx 10
		pack $top.parent -side top -expand yes -fill x -pady 5 -padx 10

		ttk::labelframe $top.group -text "Name"
		ttk::entry $top.group.e -width 40 -textvariable ::gorilla::renameGroupName
		pack $top.group.e -side top -expand yes -fill x -pady 5 -padx 10
		pack $top.group -side top -expand yes -fill x -pady 5 -padx 10
		bind $top.group.e <Shift-Tab> "after 0 \"focus $top.parent.e\""

		set sep2 [ttk::separator $top.sep2 -orient horizontal]
		pack $sep2 -side top -fill x -pady 10

		ttk::frame $top.buts
		set but1 [ttk::button $top.buts.b1 -width 15 -text "OK" \
			-command "set ::gorilla::guimutex 1"]
		set but2 [ttk::button $top.buts.b2 -width 15 -text [mc "Cancel"] \
			-command "set ::gorilla::guimutex 2"]
		pack $but1 $but2 -side left -pady 10 -padx 20
		pack $top.buts

		bind $top.parent.e <Return> "set ::gorilla::guimutex 1"
		bind $top.group.e <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b1 <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b2 <Return> "set ::gorilla::guimutex 2"

		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyRenameGroupDialog
	} else {
		wm deiconify $top
	}

	set ::gorilla::renameGroupParent $parentName
	set ::gorilla::renameGroupName $groupName

	set oldGrab [grab current .]

	update idletasks
	raise $top
	focus $top.group.e
	catch {grab $top}

	while {42} {
		ArrangeIdleTimeout
		set ::gorilla::guimutex 0
		vwait ::gorilla::guimutex

		if {$::gorilla::guimutex != 1} {
				break
		}

		set newParent [$top.parent.e get]
		set newGroup [$top.group.e get]

		#
		# Validate that both group names are valid
		#

		if {$newGroup == ""} {
				tk_messageBox -parent $top \
					-type ok -icon error -default ok \
					-title "Invalid Group Name" \
					-message "The group name can not be empty."
				continue
		}

		if {[catch {
				set newParents [pwsafe::db::splitGroup $newParent]
		}]} {
				tk_messageBox -parent $top \
					-type ok -icon error -default ok \
					-title "Invalid Group Name" \
					-message "The name of the group's parent node\
					is invalid."
				continue
		}

		#
		# if we got this far, all is well
		#

		break
	}

	if {$oldGrab != ""} {
		catch {grab $oldGrab}
	} else {
		catch {grab release $top}
	}

	wm withdraw $top

	if {$::gorilla::guimutex != 1} {
		return
	}

	if {$parentName == $newParent && $groupName == $newGroup} {
		#
		# Unchanged
		#
		set ::gorilla::status [mc "Group name unchanged."]
		return
	}

	#
	# See if the parent of the new group exists, or create it
	#

	set destparentnode [AddGroupToTree $newParent]
	set destparentdata [$::gorilla::widgets(tree) item $destparentnode -values]
	set destparenttype [lindex $destparentdata 0]

	#
	# Works nearly the same as dragging and dropping
	#

	#
	# When we are moving a group, make sure that destination is not a
	# child of this group
	#

	set destiter $destparentnode
	while {$destiter != "RootNode"} {
		if {$destiter == $node} {
				break
		}
		set destiter [$::gorilla::widgets(tree) parent $destiter]
	}

	if {$destiter != "RootNode" || $node == "RootNode"} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "Can Not Move Node" \
			-message "Can not move a group to a subgroup\
			of itself."
		return
	}

	#
	# Move recursively
	#

	if {$newGroup != ""} {
		lappend newParents $newGroup
	}

	set newParentName [pwsafe::db::concatGroups $newParents]
	set newParentNode [AddGroupToTree $newParentName]

	foreach child [$::gorilla::widgets(tree) children $node] {
		set childdata [$::gorilla::widgets(tree) item $child -values]
		set childtype [lindex $childdata 0]

		if {$childtype == "Login"} {
				set rn [lindex $childdata 1]
				$::gorilla::db setFieldValue $rn 2 $newParentName
				$::gorilla::widgets(tree) delete $child
				AddRecordToTree $rn
		} else {
				MoveTreeNodeRek $child $newParents
		}

	}

	unset ::gorilla::groupNodes($fullGroupName)
	$::gorilla::widgets(tree) item $newParentNode \
		-open [$::gorilla::widgets(tree) item $node -open]
	$::gorilla::widgets(tree) delete $node
	set ::gorilla::status [mc "Group renamed."]
	MarkDatabaseAsDirty
}


# ----------------------------------------------------------------------
# Export Database
# ----------------------------------------------------------------------
#

proc gorilla::DestroyExportDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::Export {} {
		ArrangeIdleTimeout
		set top .export

		if {![info exists ::gorilla::preference(exportIncludePassword)]} {
	set ::gorilla::preference(exportIncludePassword) 0
		}

		if {![info exists ::gorilla::preference(exportIncludeNotes)]} {
	set ::gorilla::preference(exportIncludeNotes) 1
		}

		if {![info exists ::gorilla::preference(exportAsUnicode)]} {
	set ::gorilla::preference(exportAsUnicode) 0
		}

		if {![info exists ::gorilla::preference(exportFieldSeparator)]} {
	set ::gorilla::preference(exportFieldSeparator) ","
		}

		if {![info exists ::gorilla::preference(exportShowWarning)]} {
	set ::gorilla::preference(exportShowWarning) 1
		}

		if {$::gorilla::preference(exportShowWarning)} {
			set answer [tk_messageBox -parent . \
					-type yesno -icon warning -default no \
					-title [mc "Export Security Warning"] \
					-message [mc "You are about to export the password\
					database to a plain-text file. The file will\
					not be encrypted or password-protected. Anybody\
					with access can read the file, and learn your\
					user names and passwords. Make sure to store the\
					file in a secure location. Do you want to\
					continue?"] ]
			if {$answer != "yes"} {
					return
			}
		}

		if {![info exists ::gorilla::dirName]} {
			if {[tk windowingsystem] == "aqua"} {
				set ::gorilla::dirName "~/Documents"
			} else {
			# Windows-Abfrage auch nötig ...
				set ::gorilla::dirName [pwd]
			}
		}
			
		set types {
	{{Text Files} {.txt}}
	{{CSV Files} {.csv}}
	{{All Files} *}
		}

		set fileName [tk_getSaveFile -parent . \
			-title [mc "Export password database as text ..."] \
			-defaultextension ".txt" \
			-filetypes $types \
			-initialdir $::gorilla::dirName]

		if {$fileName == ""} {
	return
		}

		set nativeName [file nativename $fileName]

		set myOldCursor [. cget -cursor]
		. configure -cursor watch
		update idletasks

		if {[catch {
	set txtFile [open $fileName "w"]
		} oops]} {
	. configure -cursor $myOldCursor
	tk_messageBox -parent . -type ok -icon error -default ok \
			-title "Error Exporting Database" \
			-message "Failed to export password database to\
		$nativeName: $oops"
	return
		}

		set ::gorilla::status [mc "Exporting ..."]
		update idletasks

		if {$::gorilla::preference(exportAsUnicode)} {
	#
	# Write BOM in binary mode, then switch to Unicode
	#

	fconfigure $txtFile -encoding binary

	if {[info exists ::tcl_platform(byteOrder)]} {
			switch -- $::tcl_platform(byteOrder) {
		littleEndian {
				puts -nonewline $txtFile "\xff\xfe"
		}
		bigEndian {
				puts -nonewline $txtFile "\xfe\xff"
		}
			}
	}

	fconfigure $txtFile -encoding unicode
		}

		set separator [subst -nocommands -novariables $::gorilla::preference(exportFieldSeparator)]

		foreach rn [$::gorilla::db getAllRecordNumbers] {
	# UUID
	if {[$::gorilla::db existsField $rn 1]} {
			puts -nonewline $txtFile [$::gorilla::db getFieldValue $rn 1]
	}
	puts -nonewline $txtFile $separator
	# Group
	if {[$::gorilla::db existsField $rn 2]} {
			puts -nonewline $txtFile [$::gorilla::db getFieldValue $rn 2]
	}
	puts -nonewline $txtFile $separator
	# Title
	if {[$::gorilla::db existsField $rn 3]} {
			puts -nonewline $txtFile [$::gorilla::db getFieldValue $rn 3]
	}
	puts -nonewline $txtFile $separator
	# Username
	if {[$::gorilla::db existsField $rn 4]} {
			puts -nonewline $txtFile [$::gorilla::db getFieldValue $rn 4]
	}
	puts -nonewline $txtFile $separator
	# Password
	if {$::gorilla::preference(exportIncludePassword)} {
			if {[$::gorilla::db existsField $rn 6]} {
		puts -nonewline $txtFile [$::gorilla::db getFieldValue $rn 6]
			}
	} else {
			puts -nonewline $txtFile "********"
	}
	puts -nonewline $txtFile $separator
	if {$::gorilla::preference(exportIncludeNotes)} {
			if {[$::gorilla::db existsField $rn 5]} {
		puts -nonewline $txtFile \
				[string map {\\ \\\\ \" \\\" \t \\t \n \\n} \
			 [$::gorilla::db getFieldValue $rn 5]]
			}
	}
	puts $txtFile ""
		}

		catch {close $txtFile}
		. configure -cursor $myOldCursor
		set ::gorilla::status [mc "Database exported."]
}

# ----------------------------------------------------------------------
# Mark database as dirty
# ----------------------------------------------------------------------

proc gorilla::MarkDatabaseAsDirty {} {
	set ::gorilla::dirty 1
	$::gorilla::widgets(tree) item "RootNode" -tags red

	if {[info exists ::gorilla::db]} {
		if {[$::gorilla::db getPreference "SaveImmediately"]} {
			
			if {[info exists ::gorilla::fileName]} {
				gorilla::Save
			} else {
				gorilla::SaveAs
			}
		}
	}

	UpdateMenu
}

# ----------------------------------------------------------------------
# Save file
# ----------------------------------------------------------------------
#
# what with name1 name2 op?

proc gorilla::SavePercentTrace {name1 name2 op} {
	if {![info exists ::gorilla::savePercentLastUpdate]} {
		set ::gorilla::savePercentLastUpdate [clock clicks -milliseconds]
		return
	}

	set now [clock clicks -milliseconds]
	set td [expr {$now - $::gorilla::savePercentLastUpdate}]
	if {$td < 100} {
		return
	}

	set ::gorilla::savePercentLastUpdate $now

	if {$::gorilla::savePercent > 0} {
		set ::gorilla::status [format "Saving ... %2.0f %%" $::gorilla::savePercent]
		update idletasks
	}
}

# ----------------------------------------------------------------------
# Merge file
# ----------------------------------------------------------------------
#

variable gorilla::fieldNames [list "" \
	"UUID" \
	"group name" \
	"title" \
	"user name" \
	"notes" \
	"password" \
	"creation time" \
	"password modification time" \
	"last access time" \
	"password lifetime" \
	"password policy" \
	"last modification time"]

proc gorilla::DestroyMergeReport {} {
	ArrangeIdleTimeout
	set top .mergeReport
	catch {destroy $top}
	unset ::gorilla::toplevel($top)
}

proc gorilla::DestroyDialog { top } {
	ArrangeIdleTimeout
	catch {destroy $top}
	unset ::gorilla::toplevel($top)
}

proc gorilla::Merge {} {
	set openInfo [OpenDatabase [mc "Merge Password Database" "" 0]]
	# set openInfo [OpenDatabase "Merge Password Database" "" 0]
	# enthält [list $fileName $newdb]
	
	set action [lindex $openInfo 0]

	if {$action != "Open"} {
		return
	}

	set ::gorilla::status [mc "Merging "]

	set fileName [lindex $openInfo 1]
  set newdb [lindex $openInfo 2]
	set nativeName [file nativename $fileName]

	set totalLogins 0
	set addedNodes [list]
	set conflictNodes [list]
	set identicalLogins 0

	set addedReport [list]
	set conflictReport [list]
	set identicalReport [list]
	set totalRecords [llength [$newdb getAllRecordNumbers]]

	foreach nrn [$newdb getAllRecordNumbers] {
		incr totalLogins

		set percent [expr {int(100.*$totalLogins/$totalRecords)}]
		set ::gorilla::status "Merging ($percent% done) ..."
		update idletasks

		set ngroup ""
		set ntitle ""
		set nuser ""

		if {[$newdb existsField $nrn 2]} {
				set ngroup [$newdb getFieldValue $nrn 2]
		}

		if {[$newdb existsField $nrn 3]} {
				set ntitle [$newdb getFieldValue $nrn 3]
		}

		if {[$newdb existsField $nrn 4]} {
				set nuser [$newdb getFieldValue $nrn 4]
		}

		#
		# See if the current database has a login with the same,
		# group, title and user
		#

		set found 0

		if {$ngroup == "" || [info exists ::gorilla::groupNodes($ngroup)]} {
	    if {$ngroup != ""} {
				set parent $::gorilla::groupNodes($ngroup)
	    } else {
				set parent "RootNode"
	    }
	
			foreach node [$::gorilla::widgets(tree) children $parent] {
				set data [$::gorilla::widgets(tree) item $node -values]
				set type [lindex $data 0]

				if {$type != "Login"} {
						continue
				}

				set rn [lindex $data 1]

				set title ""
				set user ""

				if {[$::gorilla::db existsField $rn 3]} {
					set title [$::gorilla::db getFieldValue $rn 3]
				}

				if {[$::gorilla::db existsField $rn 4]} {
					set user [$::gorilla::db getFieldValue $rn 4]
				}

				if {[string equal $ntitle $title] && \
					[string equal $nuser $user]} {
					set found 1
					break
				}
			}
		}

		if {[info exists title]} {
				pwsafe::int::randomizeVar title user
		}

		#
		# If a record with the same group, title and user was found,
		# see if the other fields are also the same.
		#

		if {$found} {
				#
				# See if they both define the same fields. If one defines
				# a field that the other doesn't have, the logins can not
				# be identical. This works both ways. However, ignore
				# timestamps and the UUID, which may go AWOL between
				# different Password Safe clones.
				#

			set nfields [$newdb getFieldsForRecord $nrn]
			set fields [$::gorilla::db getFieldsForRecord $rn]
			set identical 1

			foreach nfield $nfields {
				if {$nfield == 1 || $nfield == 7 || $nfield == 8 || \
					$nfield == 9 || $nfield == 12} {
					continue
				}
				if {[$newdb getFieldValue $nrn $nfield] == ""} {
					continue
				}
				if {[lsearch -integer -exact $fields $nfield] == -1} {
					set reason "existing login is missing "
					if {$nfield > 0 && \
						$nfield < [llength $::gorilla::fieldNames]} {
						append reason "the " \
							[lindex $::gorilla::fieldNames $nfield] \
							" field"
					} else {
						append reason "field number $nfield"
					}
					set identical 0
					break
				}
			}

			if {$identical} {
				foreach field $fields {
					if {$field == 1 || $field == 7 || $field == 8 || \
						$field == 9 || $field == 12} {
						continue
					}
					if {[$::gorilla::db getFieldValue $rn $field] == ""} {
						continue
					}
					if {[lsearch -integer -exact $nfields $field] == -1} {
						set reason "merged login is missing "
						if {$field > 0 && \
							$field < [llength $::gorilla::fieldNames]} {
							append reason "the " \
									[lindex $::gorilla::fieldNames $field] \
									" field"
						} else {
							append reason "field number $field"
						}
						set identical 0
						break
					}
				}
			}

			#
			# See if fields have the same content
			#
			
			if {$identical} {
				foreach field $fields {
					if {$field == 1 || $field == 7 || $field == 8 || \
						$field == 9 || $field == 12} {
						continue
					}
					if {[$::gorilla::db getFieldValue $rn $field] == "" && \
						[lsearch -integer -exact $nfields $field] == -1} {
						continue
					}
					if {![string equal [$newdb getFieldValue $nrn $field] \
						[$::gorilla::db getFieldValue $rn $field]]} {
						set reason ""
						if {$field > 0 && \
							$field < [llength $::gorilla::fieldNames]} {
								append reason \
									[lindex $::gorilla::fieldNames $field] \
									" differs"
						} else {
								append reason "field number $field differs"
						}
						set identical 0
						break
					}
				}
			}
		}
		# not found
		#
		# If the two records are not identical, then we have a conflict.
		# Add the new record, but with a modified title.
		#
		# If the record has a "Last Modified" field, append that
		# timestamp to the title.
		#
		# Else, append " - merged <timestamp>" to the new record.
		#

		if {$found && !$identical} {
			set timestampFormat "%Y-%m-%d %H:%M:%S"

			if {[$newdb existsField $nrn 3]} {
				set title [$newdb getFieldValue $nrn 3]
			} else {
				set title "<No Title>"
			}

			if {[set index [string first " - modified " $title]] >= 0} {
				set title [string range $title 0 [expr {$index-1}]]
			} elseif {[set index [string first " - merged " $title]] >= 0} {
				set title [string range $title 0 [expr {$index-1}]]
			}

			if {[$newdb existsField $nrn 12]} {
				append title " - modified " [clock format \
			[$newdb getFieldValue $nrn 12] \
			-format $timestampFormat]
			} else {
				append title " - merged " [clock format \
				[clock seconds] \
				-format $timestampFormat]
			}
			$newdb setFieldValue $nrn 3 $title
			pwsafe::int::randomizeVar title
		}

		#
		# Add the record to the database, if this is either a new login
		# that does not exist in this database, or if the login was found,
		# but not identical.
		#

		if {!$found || !$identical} {
			set rn [$::gorilla::db createRecord]

			foreach field [$newdb getFieldsForRecord $nrn] {
				$::gorilla::db setFieldValue $rn $field \
				[$newdb getFieldValue $nrn $field]
			}

			set node [AddRecordToTree $rn]

			if {$found && !$identical} {
				#
				# Remember that there was a conflict
				#

				lappend conflictNodes $node

				set report "Conflict for login $ntitle"
				if {$ngroup != ""} {
					append report " (in group $ngroup)"
				}
				append report ": " $reason "."
				lappend conflictReport $report

				#
				# Make sure that this node is visible
				#

				set parent [$::gorilla::widgets(tree) parent $node]

				while {$parent != "RootNode"} {
					$::gorilla::widgets(tree) item $parent -open 1
					set parent [$::gorilla::widgets(tree) parent $parent]
				}

			} else {
				lappend addedNodes $node
				set report "Added login $ntitle"
				if {$ngroup != ""} {
					append report " (in Group $ngroup)"
				}
				append report "."
				lappend addedReport $report
			}
		} else {
			incr identicalLogins
			set report "Identical login $ntitle"
			if {$ngroup != ""} {
				append report " (in Group $ngroup)"
			}
			append report "."
			lappend identicalReport $report
		}

		pwsafe::int::randomizeVar ngroup ntitle nuser
	}

	itcl::delete object $newdb
	MarkDatabaseAsDirty

	set numAddedLogins [llength $addedNodes]
	set numConflicts [llength $conflictNodes]

	set message "Merged "
	append message $nativeName "; " $totalLogins " "

	if {$totalLogins == 1} {
		append message "login, "
	} else {
		append message "logins, "
	}

	append message $identicalLogins " identical, "
	append message $numAddedLogins " added, "
	append message $numConflicts " "

	if {$numConflicts == 1} {
		append message "conflict."
	} else {
		append message "conflicts."
	}

	set ::gorilla::status $message

	if {$numConflicts > 0} {
		set default "yes"
		set icon "warning"
	} else {
		set default "no"
		set icon "info"
	}

	set answer [tk_messageBox -parent . -type yesno \
		-icon $icon -default $default \
		-title "Merge Results" \
		-message "$message Do you want to view a\
		detailed report?"]

	if {$answer != "yes"} {
		return
	}

	set top ".mergeReport"

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		wm title $top "Merge Report for $nativeName"

		set text [text $top.text -relief sunken -width 100 -wrap none \
		-yscrollcommand "$top.vsb set"]

		if {[tk windowingsystem] ne "aqua"} {
			ttk::scrollbar $top.vsb -orient vertical -command "$top.text yview"
		} else {
			scrollbar $top.vsb -orient vertical -command "$top.text yview"
		}
		## Arrange the tree and its scrollbars in the toplevel
		lower [ttk::frame $top.dummy]
		pack $top.dummy -fill both -fill both -expand 1
		grid $top.text $top.vsb -sticky nsew -in $top.dummy
		grid columnconfigure $top.dummy 0 -weight 1
		grid rowconfigure $top.dummy 0 -weight 1
		
		set botframe [ttk::frame $top.botframe]
		set botbut [ttk::button $botframe.but -width 10 -text [mc "Close"] \
			-command "gorilla::DestroyMergeReport"]
		pack $botbut
		pack $botframe -side top -fill x -pady 10
		
		bind $top <Prior> "$text yview scroll -1 pages; break"
		bind $top <Next> "$text yview scroll 1 pages; break"
		bind $top <Up> "$text yview scroll -1 units"
		bind $top <Down> "$text yview scroll 1 units"
		bind $top <Home> "$text yview moveto 0"
		bind $top <End> "$text yview moveto 1"
		bind $top <Return> "gorilla::DestroyMergeReport"
		
		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyMergeReport
				
	} else {
		wm deiconify $top
		set text "$top.text"
		set botframe "$top.botframe"
	}

		$text configure -state normal
		$text delete 1.0 end

		$text insert end $message
		$text insert end "\n\n"

		$text insert end [string repeat "-" 70]
		$text insert end "\n"
		$text insert end "Conflicts\n"
		$text insert end [string repeat "-" 70]
		$text insert end "\n"
		$text insert end "\n"
		if {[llength $conflictReport] > 0} {
			foreach report $conflictReport {
				$text insert end $report
				$text insert end "\n"
			}
		} else {
			$text insert end "None.\n"
		}
		$text insert end "\n"
		$text insert end [string repeat "-" 70]
		$text insert end "\n"
		$text insert end "Added Logins\n"
		$text insert end [string repeat "-" 70]
		$text insert end "\n"
		$text insert end "\n"
		if {[llength $addedReport] > 0} {
			foreach report $addedReport {
				$text insert end $report
				$text insert end "\n"
			}
		} else {
			$text insert end "None.\n"
		}
		$text insert end "\n"

		$text insert end [string repeat "-" 70]
		$text insert end "\n"
		$text insert end "Identical Logins\n"
		$text insert end [string repeat "-" 70]
		$text insert end "\n"
		$text insert end "\n"
		if {[llength $identicalReport] > 0} {
			foreach report $identicalReport {
				$text insert end $report
				$text insert end "\n"
			}
		} else {
			$text insert end "None.\n"
		}
		$text insert end "\n"

		$text configure -state disabled

		update idletasks
		wm deiconify $top
		raise $top
		focus $botframe.but
}


proc gorilla::Save {} {
	ArrangeIdleTimeout

	set myOldCursor [. cget -cursor]
	. configure -cursor watch
	update idletasks

	#
	# Create backup file, if desired
	#

	if {[info exists ::gorilla::preference(keepBackupFile)] && \
			$::gorilla::preference(keepBackupFile)} {
		set backupFileName [file rootname $::gorilla::fileName]
		append backupFileName ".bak"
		if {[catch {
			file copy -force -- $::gorilla::fileName $backupFileName
			} oops]} {
			. configure -cursor $myOldCursor
			set backupNativeName [file nativename $backupFileName]
			tk_messageBox -parent . -type ok -icon error -default ok \
				-title "Error Saving Database" \
				-message "Failed to make backup copy of password \
				database as $backupNativeName: $oops"
			return 0
		}
	}

	set nativeName [file nativename $::gorilla::fileName]
	#
	# Determine file version. If there is a header field of type 0,
	# it should indicate the version. Otherwise, default to version 2.
	#

	set majorVersion 2

	if {[$::gorilla::db hasHeaderField 0]} {
		set version [$::gorilla::db getHeaderField 0]

		if {[lindex $version 0] == 3} {
			set majorVersion 3
		}
	}
	set ::gorilla::savePercent 0
	trace add variable ::gorilla::savePercent [list "write"] ::gorilla::SavePercentTrace

	# verhindert einen grauen Fleck bei Speichervorgang
	update

	if {[catch {pwsafe::writeToFile $::gorilla::db $nativeName $majorVersion \
	::gorilla::savePercent} oops]} {
		trace remove variable ::gorilla::savePercent [list "write"] \
				::gorilla::SavePercentTrace
		unset ::gorilla::savePercent

		. configure -cursor $myOldCursor
		tk_messageBox -parent . -type ok -icon error -default ok \
			-title "Error Saving Database" \
			-message "Failed to save password database as\
			$nativeName: $oops"
		return 0
	}

	trace remove variable ::gorilla::savePercent [list "write"] \
		::gorilla::SavePercentTrace
	unset ::gorilla::savePercent

	. configure -cursor $myOldCursor
	# set ::gorilla::status [mc "Password database saved as $nativeName"] 
	set ::gorilla::status [mc "Password database saved."] 
	set ::gorilla::dirty 0
	$::gorilla::widgets(tree) item "RootNode" -tags black

	UpdateMenu
	return 1
}

#
# ----------------------------------------------------------------------
# Save As
# ----------------------------------------------------------------------
#

proc gorilla::SaveAs {} {
	ArrangeIdleTimeout

	if {![info exists ::gorilla::db]} {
		tk_messageBox -parent . -type ok -icon error -default ok \
			-title "Nothing To Save" \
			-message "No password database to save."
		return 1
	}

	#
	# Determine file version. If there is a header field of type 0,
	# it should indicate the version. Otherwise, default to version 2.
	#

	set majorVersion 2

	if {[$::gorilla::db hasHeaderField 0]} {
		set version [$::gorilla::db getHeaderField 0]

		if {[lindex $version 0] == 3} {
			set majorVersion 3
		}
	}
	if {$majorVersion == 3} {
		set defaultExtension ".psafe3"
	} else {
		set defaultExtension ".dat"
	}

		#
		# Query user for file name
		#

		set types {
	{{Password Database Files} {.psafe3 .dat}}
	{{All Files} *}
		}

		if {![info exists ::gorilla::dirName]} {
			if {[tk windowingsystem] == "aqua"} {
				set ::gorilla::dirName "~/Documents"
			} else {
			# Windows-Abfrage auch nötig ...
				set ::gorilla::dirName [pwd]
			}
		}

		set fileName [tk_getSaveFile -parent . \
			-title "Save password database ..." \
			-filetypes $types \
			-initialdir $::gorilla::dirName]
						# -defaultextension $defaultExtension \

		if {$fileName == ""} {
	return 0
		}

	# Dateiname auf Default Extension testen 
	# not necessary
	# -defaultextension funktioniert nur auf Windowssystemen und Mac
	# set fileName [gorilla::CheckDefaultExtension $fileName $defaultExtension]
	set nativeName [file nativename $fileName]
	
	set myOldCursor [. cget -cursor]
	. configure -cursor watch
	update idletasks

		#
		# Create backup file, if desired
		#

		if {[info exists ::gorilla::preference(keepBackupFile)] && \
			$::gorilla::preference(keepBackupFile) && \
			[file exists $fileName]} {
	set backupFileName [file rootname $fileName]
	append backupFileName ".bak"
	set ::gorilla::status $backupFileName
	if {[catch {
			file copy -force -- $fileName $backupFileName
	} oops]} {
			. configure -cursor $myOldCursor
			set backupNativeName [file nativename $backupFileName]
			tk_messageBox -parent . -type ok -icon error -default ok \
				-title "Error Saving Database" \
				-message "Failed to make backup copy of password \
				database as $backupNativeName: $oops"
			return 0
	}
		}

		set ::gorilla::savePercent 0
		trace add variable ::gorilla::savePercent [list "write"] \
	::gorilla::SavePercentTrace

		if {[catch {
	pwsafe::writeToFile $::gorilla::db $fileName $majorVersion ::gorilla::savePercent
		} oops]} {
	trace remove variable ::gorilla::savePercent [list "write"] \
			::gorilla::SavePercentTrace
	unset ::gorilla::savePercent

	. configure -cursor $myOldCursor
	tk_messageBox -parent . -type ok -icon error -default ok \
		-title "Error Saving Database" \
		-message "Failed to save password database as\
		$nativeName: $oops"
	return 0
		}

		trace remove variable ::gorilla::savePercent [list "write"] \
	::gorilla::SavePercentTrace
		unset ::gorilla::savePercent

		. configure -cursor $myOldCursor
		set ::gorilla::dirty 0
		$::gorilla::widgets(tree) item "RootNode" -tags black
		set ::gorilla::fileName $fileName
		wm title . "Password Gorilla - $nativeName"
		$::gorilla::widgets(tree) item "RootNode" -text $nativeName
		set ::gorilla::status "Password database saved as $nativeName"

		#
		# Add file to LRU preference
		#

		if {[info exists ::gorilla::preference(lru)]} {
			set found [lsearch -exact $::gorilla::preference(lru) $nativeName]
				if {$found == -1} {
					set ::gorilla::preference(lru) [linsert $::gorilla::preference(lru) 0 $nativeName]
				} elseif {$found != 0} {
					set tmp [lreplace $::gorilla::preference(lru) $found $found]
					set ::gorilla::preference(lru) [linsert $tmp 0 $nativeName]
				}
		} else {
			set ::gorilla::preference(lru) [list $nativeName]
		}
	UpdateMenu
	$::gorilla::widgets(tree) item "RootNode" -tags black
	return 1
}


# ----------------------------------------------------------------------
# Edit a Login
# ----------------------------------------------------------------------

proc gorilla::DestroyLoginDialog {} {
	set ::gorilla::guimutex 2
}

proc gorilla::LoginDialog {rn} {
	ArrangeIdleTimeout

	#
	# Set up dialog
	#

	set top .loginDialog

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		TryResizeFromPreference $top
		wm title $top [mc "Add/Edit/View Login"]

		ttk::frame $top.l
		
		foreach {child childname} {
			group Group title Title url URL user Username pass Password} {
			set kind1 [join "$top.l.$child 1" ""]
			set kind2 [join "$top.l.$child 2" ""]
			set entry_text ::gorilla::$top.l.$child.e
			ttk::label $kind1 -text [mc "$childname:"] -anchor w -padding {10 0 0 0}
			ttk::entry $kind2 -width 40 -textvariable ::gorilla::loginDialog.$child
			grid $kind1 $kind2 -sticky ew -pady 5
		}

		ttk::label $top.l.label_notes -text [mc "Notes:"] -anchor w -padding {10 0 0 0}
		text $top.l.notes -width 40 -height 5 -wrap word
		grid $top.l.label_notes $top.l.notes -sticky nsew -pady 5
		grid rowconfigure $top.l $top.l.notes -weight 1
		grid columnconfigure $top.l $top.l.notes -weight 1
		
		ttk::label $top.l.lpwc -text [mc "Last Password Change:"] -anchor w -padding {10 0 0 0}
		ttk::label $top.l.lpwc_info -text "" -width 40 -anchor w
		grid $top.l.lpwc $top.l.lpwc_info -sticky nsew -pady 5

		ttk::label $top.l.mod -text [mc "Last Modified:"] -anchor w -padding {10 0 0 0}
		ttk::label $top.l.mod_info -text "" -width 40 -anchor w
		grid $top.l.mod $top.l.mod_info -sticky nsew -pady 5

		ttk::frame $top.r				;# frame right
		ttk::frame $top.r.top
		ttk::button $top.r.top.ok -width 16 -text "OK" -command "set ::gorilla::guimutex 1"
		ttk::button $top.r.top.c -width 16 -text [mc "Cancel"] \
			-command "set ::gorilla::guimutex 2"
		pack $top.r.top.ok $top.r.top.c -side top -padx 10 -pady 5
		pack $top.r.top -side top -pady 20

		ttk::frame $top.r.pws
		ttk::button $top.r.pws.show -width 16 -text [mc "Show Password"] \
			-command "set ::gorilla::guimutex 3"
		ttk::button $top.r.pws.gen -width 16 -text [mc "Generate Password"] \
			-command "set ::gorilla::guimutex 4"
		ttk::checkbutton $top.r.pws.override -text [mc "Override Password Policy"] \
			-variable ::gorilla::overridePasswordPolicy 
			# -justify left
		pack $top.r.pws.show $top.r.pws.gen $top.r.pws.override \
			-side top -padx 10 -pady 5
		pack $top.r.pws -side top -pady 20

		pack $top.l -side left -expand yes -fill both
		pack $top.r -side right -fill both

		#
		# Set up bindings
		#

		bind $top.l.group2 <Shift-Tab> "after 0 \"focus $top.r.top.ok\""
		bind $top.l.title2 <Shift-Tab> "after 0 \"focus $top.l.group2\""
		bind $top.l.user2 <Shift-Tab> "after 0 \"focus $top.l.title2\""
		bind $top.l.pass2 <Shift-Tab> "after 0 \"focus $top.l.user2\""
		bind $top.l.notes <Tab> "after 0 \"focus $top.r.top.ok\""
		bind $top.l.notes <Shift-Tab> "after 0 \"focus $top.l.pass2\""

		bind $top.l.group2 <Return> "set ::gorilla::guimutex 1"
		bind $top.l.title2 <Return> "set ::gorilla::guimutex 1"
		bind $top.l.user2 <Return> "set ::gorilla::guimutex 1"
		bind $top.l.pass2 <Return> "set ::gorilla::guimutex 1"
		bind $top.r.top.ok <Return> "set ::gorilla::guimutex 1"
		bind $top.r.top.c <Return> "set ::gorilla::guimutex 2"

		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyLoginDialog
	} else {
		wm deiconify $top
	}

		#
		# Configure dialog
		#
		# Die textvariable für das entry muss global sein!!!
		set ::gorilla::loginDialog.group ""
		set ::gorilla::loginDialog.title ""
		set ::gorilla::loginDialog.url ""
		set ::gorilla::loginDialog.user ""
		set ::gorilla::loginDialog.pass ""
		$top.l.notes delete 1.0 end
		$top.l.lpwc_info configure -text "<unknown>"
		$top.l.mod_info configure -text "<unknown>"

		if {[$::gorilla::db existsRecord $rn]} {
			if {[$::gorilla::db existsField $rn 2]} {
				set ::gorilla::loginDialog.group	[$::gorilla::db getFieldValue $rn 2]
			}
			if {[$::gorilla::db existsField $rn 3]} {
				set ::gorilla::loginDialog.title [$::gorilla::db getFieldValue $rn 3]
			}
			if {[$::gorilla::db existsField $rn 4]} {
				set ::gorilla::loginDialog.user [$::gorilla::db getFieldValue $rn 4]
			}
			if {[$::gorilla::db existsField $rn 5]} {
				$top.l.notes insert 1.0 [$::gorilla::db getFieldValue $rn 5]
			}
			if {[$::gorilla::db existsField $rn 6]} {
				set ::gorilla::loginDialog.pass [$::gorilla::db getFieldValue $rn 6]
			}
			if {[$::gorilla::db existsField $rn 8]} {
				$top.l.lpwc_info configure -text \
					[clock format [$::gorilla::db getFieldValue $rn 8] \
					-format "%Y-%m-%d %H:%M:%S"]
			}
			if {[$::gorilla::db existsField $rn 12]} {
				$top.l.mod_info configure -text \
					[clock format [$::gorilla::db getFieldValue $rn 12] \
					-format "%Y-%m-%d %H:%M:%S"]
			}
			if {[$::gorilla::db existsField $rn 13]} {
				set ::gorilla::loginDialog.url [$::gorilla::db getFieldValue $rn 13]
			}
		}

		if {[$::gorilla::db existsRecord $rn] && [$::gorilla::db existsField $rn 6]} {
			$top.l.pass2 configure -show "*"
			$top.r.pws.show configure -text [mc "Show Password"]
		} else {
			$top.l.pass2 configure -show ""
			$top.r.pws.show configure -text [mc "Hide Password"]
		}

		if {![info exists ::gorilla::overriddenPasswordPolicy]} {
			set ::gorilla::overriddenPasswordPolicy [GetDefaultPasswordPolicy]
		}

		if {[$::gorilla::db hasHeaderField 0] && [lindex [$::gorilla::db getHeaderField 0] 0] >= 3} {
			$top.l.url2 configure -state normal
		} else {
			# Version 2 does not have a separate URL field
			set ::gorilla::loginDialog.url "(Not available with v2 database format.)"
			$top.l.url2 configure -state disabled
		}

		#
		# Run dialog
		#

		set oldGrab [grab current .]

		update idletasks
		raise $top
		focus $top.l.title2
		catch {grab $top}

		while {42} {
			ArrangeIdleTimeout
			set ::gorilla::guimutex 0
			vwait ::gorilla::guimutex
			if {$::gorilla::guimutex == 1} {
				if {[$top.l.title2 get] == ""} {
					tk_messageBox -parent $top \
						-type ok -icon error -default ok \
						-title "Login Needs Title" \
						-message "A login must at least have a title.\
						Please enter a title for this login."
					continue
				}
				if {[ catch {pwsafe::db::splitGroup [$top.l.group2 get]} ]} {
					tk_messageBox -parent $top \
						-type ok -icon error -default ok \
						-title "Invalid Group Name" \
						-message "This login's group name is not valid."
					continue
				}
				break
			} elseif {$::gorilla::guimutex == 2} {
				break
			} elseif {$::gorilla::guimutex == 3} {
				#
				# Show Password
				#
				set show [$top.l.pass2 cget -show]
				if {$show == ""} {
					$top.l.pass2 configure -show "*"
					$top.r.pws.show configure -text [mc "Show Password"]
				} else {
					$top.l.pass2 configure -show ""
					$top.r.pws.show configure -text [mc "Hide Password"]
				}
			} elseif {$::gorilla::guimutex == 4} {
				#
				# Generate Password
				#
				if {$::gorilla::overridePasswordPolicy} {
					set settings [PasswordPolicyDialog \
						[mc "Override Password Policy"] \
						$::gorilla::overriddenPasswordPolicy]
					if {[llength $settings] == 0} {
						continue
					}
					set ::gorilla::overriddenPasswordPolicy $settings
				} else {
					set settings [GetDefaultPasswordPolicy]
				}
				if {[catch {set newPassword [GeneratePassword $settings]} oops]} {
					tk_messageBox -parent $top \
						-type ok -icon error -default ok \
						-title "Invalid Password Settings" \
						-message "The password policy settings are invalid."
					continue
				}
				set ::gorilla::loginDialog.pass $newPassword
				pwsafe::int::randomizeVar newPassword
			}
		}

		if {$oldGrab != ""} {
			catch {grab $oldGrab}
		} else {
			catch {grab release $top}
		}

		wm withdraw $top

		#
		# Canceled?
		#

		if {$::gorilla::guimutex != 1} {
			set ::gorilla::loginDialog.group ""
			set ::gorilla::loginDialog.url ""
			set ::gorilla::loginDialog.title ""
			set ::gorilla::loginDialog.user ""
			set ::gorilla::loginDialog.pass ""
			$top.l.notes delete 1.0 end
			return 0
		}

		#
		# Store fields in the database
		#

		set modified 0
		set now [clock seconds]

		set group [$top.l.group2 get]
		if {$group != ""} {
			if {![$::gorilla::db existsField $rn 2] || \
				![string equal $group [$::gorilla::db getFieldValue $rn 2]]} {
				set modified 1
			}
			$::gorilla::db setFieldValue $rn 2 $group
		} elseif {[$::gorilla::db existsField $rn 2]} {
			$::gorilla::db unsetFieldValue $rn 2
			set modified 1
		}
		set ::gorilla::loginDialog.group ""
		pwsafe::int::randomizeVar group

		set title [$top.l.title2 get]
		if {$title != ""} {
			if {![$::gorilla::db existsField $rn 3] || \
				![string equal $title [$::gorilla::db getFieldValue $rn 3]]} {
				set modified 1
			}
			$::gorilla::db setFieldValue $rn 3 $title
		} elseif {[$::gorilla::db existsField $rn 3]} {
			$::gorilla::db unsetFieldValue $rn 3
			set modified 1
		}
		set ::gorilla::loginDialog.title ""
		pwsafe::int::randomizeVar title

		set user [$top.l.user2 get]
		if {$user != ""} {
			if {![$::gorilla::db existsField $rn 4] || \
				![string equal $user [$::gorilla::db getFieldValue $rn 4]]} {
				set modified 1
			}
			$::gorilla::db setFieldValue $rn 4 $user
		} elseif {[$::gorilla::db existsField $rn 4]} {
			$::gorilla::db unsetFieldValue $rn 4
			set modified 1
		}
		set ::gorilla::loginDialog.user ""
		pwsafe::int::randomizeVar user

		set pass [$top.l.pass2 get]
		if {$pass != ""} {
			if {![$::gorilla::db existsField $rn 6] || \
				![string equal $pass [$::gorilla::db getFieldValue $rn 6]]} {
				set modified 1
				$::gorilla::db setFieldValue $rn 8 $now ;# PW mod time
			}
			$::gorilla::db setFieldValue $rn 6 $pass
		} elseif {[$::gorilla::db existsField $rn 6]} {
			$::gorilla::db unsetFieldValue $rn 6
			set modified 1
		}
		pwsafe::int::randomizeVar pass
		set ::gorilla::loginDialog.pass ""

		set notes [string trim [$top.l.notes get 1.0 end]]
		if {$notes != ""} {
			if {![$::gorilla::db existsField $rn 5] || \
				![string equal $notes [$::gorilla::db getFieldValue $rn 5]]} {
				set modified 1
			}
			$::gorilla::db setFieldValue $rn 5 $notes
		} elseif {[$::gorilla::db existsField $rn 5]} {
			$::gorilla::db unsetFieldValue $rn 5
			set modified 1
		}
		$top.l.notes delete 1.0 end
		pwsafe::int::randomizeVar notes

		if {[$top.l.url2 cget -state] == "normal"} {
			set url [$top.l.url2 get]

			if {$url != ""} {
				if {![$::gorilla::db existsField $rn 13] || \
					![string equal $url [$::gorilla::db getFieldValue $rn 13]]} {
					set modified 1
					$::gorilla::db setFieldValue $rn 8 $now ;# PW mod time
				}
				$::gorilla::db setFieldValue $rn 13 $url
			} elseif {[$::gorilla::db existsField $rn 13]} {
				$::gorilla::db unsetFieldValue $rn 13
				set modified 1
			}
			pwsafe::int::randomizeVar url
		}
		set ::gorilla::loginDialog.url ""

		if {$modified} {
			$::gorilla::db setFieldValue $rn 12 $now
		}

		return $modified
}

# ----------------------------------------------------------------------
# Rebuild Tree
# ----------------------------------------------------------------------
#

	proc gorilla::AddAllRecordsToTree {} {
		foreach rn [$::gorilla::db getAllRecordNumbers] {
			AddRecordToTree $rn
		}
}

proc gorilla::AddRecordToTree {rn} {
		if {[$::gorilla::db existsField $rn 2]} {
	set groupName [$::gorilla::db getFieldValue $rn 2]
		} else {
	set groupName ""
		}

		set parentNode [AddGroupToTree $groupName]

		if {[$::gorilla::db existsField $rn 3]} {
	set title [$::gorilla::db getFieldValue $rn 3]
		} else {
	set title ""
		}

		if {[$::gorilla::db existsField $rn 4]} {
	append title " \[" [$::gorilla::db getFieldValue $rn 4] "\]"
		}

		#
		# Insert the new login in alphabetical order, after all groups
		#

		# set childNodes [$::gorilla::widgets(tree) nodes $parentNode]
		set childNodes [$::gorilla::widgets(tree) children $parentNode]

		for {set i 0} {$i < [llength $childNodes]} {incr i} {
	set childNode [lindex $childNodes $i]
	set childData [$::gorilla::widgets(tree) item $childNode -values]
	if {[lindex $childData 0] != "Login"} {
			continue
	}

	set childName [$::gorilla::widgets(tree) item $childNode -text]
	if {[string compare $title $childName] < 0} {
		break
	}
		}

		if {$i >= [llength $childNodes]} {
	set i "end"
		}

		set nodename "node[incr ::gorilla::uniquenodeindex]"
		$::gorilla::widgets(tree) insert $parentNode $i -id $nodename \
			-open 0	\
			-image $::gorilla::images(login) \
			-text $title \
			-values [list Login $rn]
			# -drawcross never
		return $nodename
}

proc gorilla::AddGroupToTree {groupName} {
	if {[info exists ::gorilla::groupNodes($groupName)]} {
		set parentNode $::gorilla::groupNodes($groupName)
	} elseif {$groupName == ""} {
		set parentNode "RootNode"
	} else {
		set parentNode "RootNode"
		set partialGroups [list]
		foreach group [pwsafe::db::splitGroup $groupName] {
			lappend partialGroups $group
			set partialGroupName [pwsafe::db::concatGroups $partialGroups]
			if {[info exists ::gorilla::groupNodes($partialGroupName)]} {
				set parentNode $::gorilla::groupNodes($partialGroupName)
			} else {
				set childNodes [$::gorilla::widgets(tree) children $parentNode]
	
				#
				# Insert group in alphabetical order, before all logins
				#

				for {set i 0} {$i < [llength $childNodes]} {incr i} {
					set childNode [lindex $childNodes $i]
					set childData [$::gorilla::widgets(tree) item $childNode -values]
					if {[lindex $childData 0] != "Group"} {
						break
					}

					set childName [$::gorilla::widgets(tree) item $childNode -text]
					if {[string compare $group $childName] < 0} {
						break
					}
				}
				
				if {$i >= [llength $childNodes]} {
					set i "end"
				}
				
				set nodename "node[incr ::gorilla::uniquenodeindex]"
				
				$::gorilla::widgets(tree) insert $parentNode	$i -id $nodename \
					-open 0 \
					-image $::gorilla::images(group) \
					-text $group \
					-values [list Group $partialGroupName]
				
				set parentNode $nodename
				set ::gorilla::groupNodes($partialGroupName) $nodename
			}
		}
	}

	return $parentNode
}


#
# Update Menu items
#


proc gorilla::UpdateMenu {} {
	set selection [$::gorilla::widgets(tree) selection]
	
	if {[llength $selection] == 0} {
		setmenustate $::gorilla::widgets(main) group disabled
		setmenustate $::gorilla::widgets(main) login disabled
	} else {
		set node [lindex $selection 0]
		set data [$::gorilla::widgets(tree) item $node -values]
		set type [lindex $data 0]

		if {$type == "Group" || $type == "Root"} {
			setmenustate $::gorilla::widgets(main) group normal
			setmenustate $::gorilla::widgets(main) login disabled
		} else {
			setmenustate $::gorilla::widgets(main) group disabled
			setmenustate $::gorilla::widgets(main) login normal
		}
	}

	if {[info exists ::gorilla::fileName] && [info exists ::gorilla::db] && $::gorilla::dirty} {
		setmenustate $::gorilla::widgets(main) save normal
	} else {
		setmenustate $::gorilla::widgets(main) save disabled
	}

	if {[info exists ::gorilla::db]} {
		setmenustate $::gorilla::widgets(main) open normal
		} else {
		setmenustate $::gorilla::widgets(main) open disabled
	}
}

proc gorilla::Exit {} {
	ArrangeIdleTimeout

	#
	# Protect against reentrancy, i.e., if the user clicks on the "X"
	# window manager decoration multiple times.
	#

	if {[info exists ::gorilla::exiting] && $::gorilla::exiting} {
		return
	}

	set ::gorilla::exiting 1

	#
	# If the current database was modified, give user a chance to think
	#

	if {$::gorilla::dirty} {
		set myParent [grab current .]

		if {$myParent == ""} {
			set myParent "."
		}

		set answer [tk_messageBox -parent $myParent \
		-type yesnocancel -icon warning -default yes \
		-title [ mc "Save changes?" ] \
		-message [ mc "The current password database is modified.\
		Do you want to save the database?\n\
		\"Yes\" saves the database, and exits.\n\
		\"No\" discards all changes, and exits.\n\
		\"Cancel\" returns to the main menu."]]
		if {$answer == "yes"} {
			if {[info exists ::gorilla::fileName]} {
				if {![::gorilla::Save]} {
					set ::gorilla::exiting 0
				}
			} else {
				if {![::gorilla::SaveAs]} {
					set ::gorilla::exiting 0
				}
			}
		} elseif {$answer != "no"} {
			set ::gorilla::exiting 0
		}
		if {!$::gorilla::exiting} {
			return 0
		}
	}

		#
		# Save preferences
		#

		SavePreferences

		#
		# Clear the clipboard, if we were meant to do that sooner or later.
		#

		if {[info exists ::gorilla::clipboardClearId]} {
			after cancel $::gorilla::clipboardClearId
			ClearClipboard
		}

		#
		# Goodbye, cruel world
		#

		destroy .
		exit
}

proc gorilla::CopyUsername {} {
		ArrangeIdleTimeout
		clipboard clear
		clipboard append -- [::gorilla::GetSelectedUsername]
		set ::gorilla::activeSelection 1
		selection clear
		selection own .
		ArrangeToClearClipboard
		set ::gorilla::status [mc "Copied user name to clipboard."]
}

proc gorilla::CopyURL {} {
	ArrangeIdleTimeout
	clipboard clear
	set URL [gorilla::GetSelectedURL]

	if {$URL == ""} {
		set ::gorilla::status [mc "Can not copy URL to clipboard: no URL defined."]
	} else {
		clipboard append -- $URL
		set ::gorilla::activeSelection 3
		selection clear
		selection own .
		ArrangeToClearClipboard
		set ::gorilla::status [mc "Copied URL to clipboard."]
	}
}


# ----------------------------------------------------------------------
# Clear clipboard
# ----------------------------------------------------------------------
#

proc gorilla::ClearClipboard {} {
	clipboard clear
	clipboard append -- ""

	if {[selection own] == "."} {
		selection clear
	}

	set ::gorilla::activeSelection 0
	set ::gorilla::status [mc "Clipboard cleared."]
	catch {unset ::gorilla::clipboardClearId}
}

# ----------------------------------------------------------------------
# Clear the clipboard after a configurable number of seconds
# ----------------------------------------------------------------------
#

proc gorilla::ArrangeToClearClipboard {} {
	if {[info exists ::gorilla::clipboardClearId]} {
		after cancel $::gorilla::clipboardClearId
	}

	if {![info exists ::gorilla::preference(clearClipboardAfter)] || \
		$::gorilla::preference(clearClipboardAfter) == 0} {
		catch {unset ::gorilla::clipboardClearId}
		return
	}

	set seconds $::gorilla::preference(clearClipboardAfter)
	set mseconds [expr {$seconds * 1000}]
	set ::gorilla::clipboardClearId [after $mseconds ::gorilla::ClearClipboard]
}


# ----------------------------------------------------------------------
# Arrange for an Idle Timeout after a number of minutes
# ----------------------------------------------------------------------
#

proc gorilla::ArrangeIdleTimeout {} {
	if {[info exists ::gorilla::idleTimeoutTimerId]} {
		after cancel $::gorilla::idleTimeoutTimerId
	}

	if {[info exists ::gorilla::db]} {
		set minutes [$::gorilla::db getPreference "IdleTimeout"]

		if {![$::gorilla::db getPreference "LockOnIdleTimeout"] || $minutes <= 0} {
			catch {unset ::gorilla::idleTimeoutTimerId}
			return
		}

	set seconds [expr {$minutes * 60}]
	set mseconds [expr {$seconds * 1000}]
	set ::gorilla::idleTimeoutTimerId [after $mseconds ::gorilla::IdleTimeout]
	}
}


# ----------------------------------------------------------------------
# Idle Timeout
# ----------------------------------------------------------------------


proc gorilla::IdleTimeout {} {
		LockDatabase
}

# ----------------------------------------------------------------------
# Lock Database
# ----------------------------------------------------------------------
#

proc gorilla::CloseLockedDatabaseDialog {} {
		set ::gorilla::lockedMutex 2
}

proc gorilla::LockDatabase {} {
	if {![info exists ::gorilla::db]} {
		return
	}

	if {[info exists ::gorilla::isLocked] && $::gorilla::isLocked} {
		return
	}

	if {[info exists ::gorilla::idleTimeoutTimerId]} {
		after cancel $::gorilla::idleTimeoutTimerId
	}

	ClearClipboard
	set ::gorilla::isLocked 1

	set oldGrab [grab current .]

	# close all open windows and remember their status
	foreach tl [array names ::gorilla::toplevel] {
		set ws [wm state $tl]
		switch -- $ws {
			normal -
			iconic -
			zoomed {
				set withdrawn($tl) $ws
				wm withdraw $tl
			}
		}
	}
	
	# Ist es wirklich notwendig, die Submenüs zu deaktivieren?
	# $::gorilla::widgets(main) setmenustate all disabled
	
	set top .lockedDialog
	if {![info exists ::gorilla::toplevel($top)]} {
		
	toplevel $top
	TryResizeFromPreference $top

	# ttk::label $top.splash -image $::gorilla::images(splash)
	# Bild packen
	# pack $top.splash -side left -fill both

	# ttk::separator $top.vsep -orient vertical
	# pack $top.vsep -side left -fill y -padx 3

	set aframe [ttk::frame $top.right -padding {10 10}]

	# Titel packen	
	# ttk::label $aframe.title -anchor center -font {Helvetica 12 bold}
	ttk::label $aframe.title -anchor center
	pack $aframe.title -side top -fill x -pady 10

	ttk::labelframe $aframe.file -text [mc "Database:"]
	ttk::entry $aframe.file.f -width 40 -state disabled
	pack $aframe.file.f -side left -padx 10 -pady 5 -fill x -expand yes
	pack $aframe.file -side top -pady 5 -fill x -expand yes

	ttk::frame $aframe.mitte
	ttk::labelframe $aframe.mitte.pw -text [mc "Password:"] 
	entry $aframe.mitte.pw.pw -width 20 -show "*" 
	# -background #FFFFCC
	pack $aframe.mitte.pw.pw -side left -padx 10 -pady 5 -fill x -expand 0
	
	pack $aframe.mitte.pw -side left -pady 5 -expand 0

	ttk::frame $aframe.mitte.buts
	set but1 [ttk::button $aframe.mitte.buts.b1 -width 10 -text "OK" \
		-command "set ::gorilla::lockedMutex 1"]
	set but2 [ttk::button $aframe.mitte.buts.b2 -width 10 -text [mc "Exit"] \
		-command "set ::gorilla::lockedMutex 2"]
	pack $but1 $but2 -side left -pady 10 -padx 10
	pack $aframe.mitte.buts -side right

	pack $aframe.mitte -side top -fill x -expand 1 -pady 15
	
	ttk::label $aframe.info -relief sunken -anchor w -padding [list 5 5 5 5]
	pack $aframe.info -side bottom -fill x -expand yes

	bind $aframe.mitte.pw.pw <Return> "set ::gorilla::lockedMutex 1"
	bind $aframe.mitte.buts.b1 <Return> "set ::gorilla::lockedMutex 1"
	bind $aframe.mitte.buts.b2 <Return> "set ::gorilla::lockedMutex 2"
		
	pack $aframe -side right -fill both -expand yes

	set ::gorilla::toplevel($top) $top
	
	wm protocol $top WM_DELETE_WINDOW gorilla::CloseLockedDatabaseDialog
		} else {
	set aframe $top.right
	wm deiconify $top
		}

		wm title $top "Password Gorilla"
		$aframe.title configure -text  [mc "Database Locked"]
		$aframe.mitte.pw.pw delete 0 end
		$aframe.info configure -text [mc "Enter the Master Password."]

		if {[info exists ::gorilla::fileName]} {
	$aframe.file.f configure -state normal
	$aframe.file.f delete 0 end
	$aframe.file.f insert 0 [file nativename $::gorilla::fileName]
	$aframe.file.f configure -state disabled
		} else {
	$aframe.file.f configure -state normal
	$aframe.file.f delete 0 end
	$aframe.file.f insert 0 [mc "<New Database>"]
	$aframe.file.f configure -state disabled
		}

		#
		# Run dialog
		#

		focus $aframe.mitte.pw.pw
		if {[catch { grab $top } oops]} {
			set ::gorilla::status "error: $oops"
		}
		
		while {42} {
	set ::gorilla::lockedMutex 0
	vwait ::gorilla::lockedMutex

	if {$::gorilla::lockedMutex == 1} {
			if {[$::gorilla::db checkPassword [$aframe.mitte.pw.pw get]]} {
		break
			}

			tk_messageBox -parent $top \
		-type ok -icon error -default ok \
		-title "Wrong Password" \
		-message "That password is not correct."
	} elseif {$::gorilla::lockedMutex == 2} {
			#
			# This may return, if the database was modified, and the user
			# answers "Cancel" to the question whether to save the database
			# or not.
			#

			gorilla::Exit
	}
		}

		foreach tl [array names withdrawn] {
			wm state $tl $withdrawn($tl)
		}

		if {$oldGrab != ""} {
			catch {grab $oldGrab}
		} else {
			catch {grab release $top}
		}

		# $::gorilla::widgets(main) setmenustate all normal

		wm withdraw $top
		set ::gorilla::status [mc "Welcome back."]

		set ::gorilla::isLocked 0

		wm deiconify .
		raise .

		ArrangeIdleTimeout
}


# ----------------------------------------------------------------------
# Prompt for a Password
# ----------------------------------------------------------------------
#

proc gorilla::DestroyGetPasswordDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::GetPassword {confirm title} {
	set top .passwordDialog-$confirm

	if {![info exists ::gorilla::toplevel($top)]} {
		if {[tk windowingsystem] == "aqua"} {
			toplevel $top -background #ededed
		} else {
			toplevel $top
		}
		TryResizeFromPreference $top

		ttk::labelframe $top.password -text $title -padding [list 10 10]
		ttk::entry $top.password.e -show "*" -width 30 -textvariable ::gorilla::passwordDialog.pw

		pack $top.password.e -side left
		pack $top.password -fill x -pady 15 -padx 15 -expand 1
		
		bind $top.password.e <KeyPress> "+::gorilla::CollectTicks"
		bind $top.password.e <KeyRelease> "+::gorilla::CollectTicks"

		if {$confirm} {
			ttk::labelframe $top.confirm -text [mc "Confirm:"] -padding [list 10 10]
			ttk::entry $top.confirm.e -show "*" -width 30 -textvariable ::gorilla::passwordDialog.c
			pack $top.confirm.e -side left
			pack $top.confirm -fill x -pady 5 -padx 15 -expand 1

			bind $top.confirm.e <KeyPress> "+::gorilla::CollectTicks"
			bind $top.confirm.e <KeyRelease> "+::gorilla::CollectTicks"
			# bind $top.confirm.e <Shift-Tab> "after 0 \"focus $top.password.e\""
			# bind $top.confirm.e <Tab> "after 0 \"focus $top.password.e\""
		}

		ttk::frame $top.buts
		set but1 [ttk::button $top.buts.b1 -width 10 -text OK \
			-command "set ::gorilla::guimutex 1"]
		set but2 [ttk::button $top.buts.b2 -width 10 -text [mc "Cancel"] \
			-command "set ::gorilla::guimutex 2"]
		pack $but1 $but2 -side left -pady 15 -padx 30
		pack $top.buts -fill x -expand 1
		
		bind $top.password.e <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b1 <Return> "set ::gorilla::guimutex 1"
		bind $top.buts.b2 <Return> "set ::gorilla::guimutex 2"

		if {$confirm} {
			bind $top.confirm.e <Return> "set ::gorilla::guimutex 1"
		}

		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyGetPasswordDialog
	} else {
		wm deiconify $top
	}

		wm title $top $title
		# $top.password configure -text ""
		set ::gorilla::passwordDialog.pw ""

		if {$confirm} {
			# $top.confirm configure -text ""
			set ::gorilla::passwordDialog.c ""
		}

		#
		# Run dialog
		#

		set oldGrab [grab current .]

		update idletasks
		raise $top
		focus $top.password.e
		catch {grab $top}

		while {42} {
			ArrangeIdleTimeout
			set ::gorilla::guimutex 0
			vwait ::gorilla::guimutex

			if {$::gorilla::guimutex != 1} {
				break
			}

			set password [$top.password.e get]

			if {$confirm} {
				set confirmed [$top.confirm.e get]

				if {![string equal $password $confirmed]} {
					tk_messageBox -parent $top \
						-type ok -icon error -default ok \
						-title [ mc "Passwords Do Not Match" ] \
						-message [ mc "The confirmed password does not match." ]
				} else {
					break
				}
			} else {
				break
			}
		}

		set ::gorilla::passwordDialog.pw ""

		if {$oldGrab != ""} {
			catch {grab $oldGrab}
		} else {
			catch {grab release $top}
		}

		wm withdraw $top

		if {$::gorilla::guimutex != 1} {
			error "canceled"
		}

		return $password
}

# ----------------------------------------------------------------------
# Default Password Policy
# ----------------------------------------------------------------------
#

proc gorilla::GetDefaultPasswordPolicy {} {
		array set defaults [list \
			length [$::gorilla::db getPreference "PWLenDefault"] \
			uselowercase [$::gorilla::db getPreference "PWUseLowercase"] \
			useuppercase [$::gorilla::db getPreference "PWUseUppercase"] \
			usedigits [$::gorilla::db getPreference "PWUseDigits"] \
			usesymbols [$::gorilla::db getPreference "PWUseSymbols"] \
			usehexdigits [$::gorilla::db getPreference "PWUseHexDigits"] \
			easytoread [$::gorilla::db getPreference "PWEasyVision"]]
		return [array get defaults]
}

proc gorilla::SetDefaultPasswordPolicy {settings} {
	array set defaults $settings
	if {[info exists defaults(length)]} {
		$::gorilla::db setPreference "PWLenDefault" $defaults(length)
	}
	if {[info exists defaults(uselowercase)]} {
		$::gorilla::db setPreference "PWUseLowercase" $defaults(uselowercase)
	}
	if {[info exists defaults(useuppercase)]} {
		$::gorilla::db setPreference "PWUseUppercase" $defaults(useuppercase)
	}
	if {[info exists defaults(usedigits)]} {
		$::gorilla::db setPreference "PWUseDigits" $defaults(usedigits)
	}
	if {[info exists defaults(usesymbols)]} {
		$::gorilla::db setPreference "PWUseSymbols" $defaults(usesymbols)
	}
	if {[info exists defaults(usehexdigits)]} {
		$::gorilla::db setPreference "PWUseHexDigits" $defaults(usehexdigits)
	}
	if {[info exists defaults(easytoread)]} {
		$::gorilla::db setPreference "PWEasyVision" $defaults(easytoread)
	}
}

# ----------------------------------------------------------------------
# Set the Password Policy
# ----------------------------------------------------------------------
#

proc gorilla::PasswordPolicy {} {
		ArrangeIdleTimeout

		if {![info exists ::gorilla::db]} {
	tk_messageBox -parent . \
		-type ok -icon error -default ok \
		-title "No Database" \
		-message "Please create a new database, or open an existing\
		database first."
	return
		}

		set oldSettings [GetDefaultPasswordPolicy]
		set newSettings [PasswordPolicyDialog "Password Policy" $oldSettings]

		if {[llength $newSettings]} {
	SetDefaultPasswordPolicy $newSettings
	set ::gorilla::status [mc "Password policy changed."]
	MarkDatabaseAsDirty
		}
}

#
# ----------------------------------------------------------------------
# Dialog box for password policy
# ----------------------------------------------------------------------
#

proc gorilla::DestroyPasswordPolicyDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::PasswordPolicyDialog {title settings} {
		ArrangeIdleTimeout

		array set ::gorilla::ppd [list \
			length 8 \
			uselowercase 1 \
			useuppercase 1 \
			usedigits 1 \
			usehexdigits 0 \
			usesymbols 0 \
			easytoread 1]
		array set ::gorilla::ppd $settings

		set top .passPolicyDialog

		if {![info exists ::gorilla::toplevel($top)]} {
	toplevel $top
	TryResizeFromPreference $top

	ttk::frame $top.plen -padding [list 0 10 0 0 ]
	ttk::label $top.plen.l -text [mc "Password Length"]
	spinbox $top.plen.s -from 1 -to 999 -increment 1 \
		-width 4 -justify right \
		-textvariable ::gorilla::ppd(length)
	pack $top.plen.l -side left
	pack $top.plen.s -side left -padx 10
	pack $top.plen -side top -anchor w -padx 10 -pady 3

	ttk::checkbutton $top.lower -text [mc "Use lowercase letters"] \
		-variable ::gorilla::ppd(uselowercase)
	ttk::checkbutton $top.upper -text [mc "Use UPPERCASE letters"] \
		-variable ::gorilla::ppd(useuppercase)
	ttk::checkbutton $top.digits -text [mc "Use digits"] \
		-variable ::gorilla::ppd(usedigits)
	ttk::checkbutton $top.hex -text [mc "Use hexadecimal digits"] \
		-variable ::gorilla::ppd(usehexdigits)
	ttk::checkbutton $top.symbols -text [mc "Use symbols (%, \$, @, #, etc.)"] \
		-variable ::gorilla::ppd(usesymbols)
	ttk::checkbutton $top.easy \
		-text [mc "Use easy to read characters only (e.g. no \"0\" or \"O\")"] \
		-variable ::gorilla::ppd(easytoread)
	pack $top.lower $top.upper $top.digits $top.hex $top.symbols \
		$top.easy -anchor w -side top -padx 10 -pady 3

	ttk::separator $top.sep -orient horizontal
	pack $top.sep -side top -fill x -pady 10

	frame $top.buts
	set but1 [ttk::button $top.buts.b1 -width 15 -text "OK" \
		-command "set ::gorilla::guimutex 1"]
	set but2 [ttk::button $top.buts.b2 -width 15 -text [mc "Cancel"] \
		-command "set ::gorilla::guimutex 2"]
	pack $but1 $but2 -side left -pady 10 -padx 20
	pack $top.buts -padx 10

	bind $top.lower <Return> "set ::gorilla::guimutex 1"
	bind $top.upper <Return> "set ::gorilla::guimutex 1"
	bind $top.digits <Return> "set ::gorilla::guimutex 1"
	bind $top.hex <Return> "set ::gorilla::guimutex 1"
	bind $top.symbols <Return> "set ::gorilla::guimutex 1"
	bind $top.easy <Return> "set ::gorilla::guimutex 1"
	bind $top.buts.b1 <Return> "set ::gorilla::guimutex 1"
	bind $top.buts.b2 <Return> "set ::gorilla::guimutex 2"

	set ::gorilla::toplevel($top) $top
	wm protocol $top WM_DELETE_WINDOW gorilla::DestroyPasswordPolicyDialog
		} else {
	wm deiconify $top
		}

		set oldGrab [grab current .]

		update idletasks
		wm title $top $title
		raise $top
		focus $top.plen.s
		catch {grab $top}

		set ::gorilla::guimutex 0
		vwait ::gorilla::guimutex

		if {$oldGrab != ""} {
			catch {grab $oldGrab}
		} else {
			catch {grab release $top}
		}

		wm withdraw $top

		if {$::gorilla::guimutex != 1} {
	return [list]
		}

		return [array get ::gorilla::ppd]
}

#
# ----------------------------------------------------------------------
# Generate a password
# ----------------------------------------------------------------------
#

proc gorilla::GeneratePassword {settings} {
		set easyLowercaseLetters "abcdefghkmnpqrstuvwxyz"
		set notEasyLowercaseLetters "ijlo"
		set easyUppercaseLetters [string toupper $easyLowercaseLetters]
		set notEasyUppercaseLetters [string toupper $notEasyLowercaseLetters]
		set easyDigits "23456789"
		set notEasyDigits "01"
		set easySymbols "+-=_@#\$%^&<>/~\\?"
		set notEasySymbols "!|()"

		array set params [list \
			length 0 \
			uselowercase 0 \
			useuppercase 0 \
			usedigits 0 \
			usehexdigits 0 \
			usesymbols 0 \
			easytoread 0]
		array set params $settings

		set symbolSet ""

		if {$params(uselowercase)} {
	append symbolSet $easyLowercaseLetters
	if {!$params(easytoread)} {
			append symbolSet $notEasyLowercaseLetters
	}
		}

		if {$params(useuppercase)} {
	append symbolSet $easyUppercaseLetters
	if {!$params(easytoread)} {
			append symbolSet $notEasyUppercaseLetters
	}
		}

		if {$params(usehexdigits)} {
	if {!$params(uselowercase)} {
			append symbolSet "0123456789abcdef"
	} else {
			append symbolSet "0123456789"
	}
		} elseif {$params(usedigits)} {
	append symbolSet $easyDigits
	if {!$params(easytoread)} {
			append symbolSet $notEasyDigits
	}
		}

		if {$params(usesymbols)} {
	append symbolSet $easySymbols
	if {!$params(easytoread)} {
			append symbolSet $notEasySymbols
	}
		}
 
		set numSymbols [string length $symbolSet]

		if {$numSymbols == 0} {
	error "invalid settings"
		}

		set generatedPassword ""
		for {set i 0} {$i < $params(length)} {incr i} {
	set rand [::isaac::rand]
	set randSymbol [expr {int($rand*$numSymbols)}]
	append generatedPassword [string index $symbolSet $randSymbol]
		}

		return $generatedPassword
}

# ----------------------------------------------------------------------
# Dialog box for database-specific preferences
# ----------------------------------------------------------------------
#

proc gorilla::DestroyDatabasePreferencesDialog {} {
		set ::gorilla::guimutex 2
}

proc gorilla::DatabasePreferencesDialog {} {
	ArrangeIdleTimeout

	set top .dbPrefsDialog

	if {![info exists ::gorilla::db]} {
		return
	}

	foreach pref {IdleTimeout IsUTF8 LockOnIdleTimeout SaveImmediately} {
		set ::gorilla::dpd($pref) [$::gorilla::db getPreference $pref]
	}

	if {!$::gorilla::dpd(LockOnIdleTimeout)} {
		set ::gorilla::dpd(IdleTimeout) 0
	}

	if {[$::gorilla::db hasHeaderField 0]} {
		set oldVersion [lindex [$::gorilla::db getHeaderField 0] 0]
	} else {
		set oldVersion 2
	}

	set ::gorilla::dpd(defaultVersion) $oldVersion

	set ::gorilla::dpd(keyStretchingIterations) \
		[$::gorilla::db cget -keyStretchingIterations]
	set oldKeyStretchingIterations $::gorilla::dpd(keyStretchingIterations)

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		wm title $top [mc "Database Preferences"]
		TryResizeFromPreference $top

		ttk::frame $top.il -padding [list 10 15 10 5]
		ttk::label $top.il.l1 -text [mc "Lock when idle after"]
		spinbox $top.il.s -from 0 -to 999 -increment 1 \
				-justify right -width 4 \
				-textvariable ::gorilla::dpd(IdleTimeout)
		ttk::label $top.il.l2 -text [mc "minutes (0=never)"]
		pack $top.il.l1 $top.il.s $top.il.l2 -side left -padx 3
		pack $top.il -side top -anchor w

		ttk::checkbutton $top.si -text [mc "Auto-save database immediately when changed"] \
			-variable ::gorilla::dpd(SaveImmediately)
		pack $top.si -anchor w -side top -pady 3 -padx 10

		ttk::checkbutton $top.ver -text [mc "Use Password Safe 3 format"] \
				-variable ::gorilla::dpd(defaultVersion) \
				-onvalue 3 -offvalue 2
		pack $top.ver -anchor w -side top -pady 3 -padx 10

		ttk::checkbutton $top.uni -text [mc "V2 Unicode support"] \
			-variable ::gorilla::dpd(IsUTF8)
		pack $top.uni -anchor w -side top -pady 3 -padx 10

		ttk::frame $top.stretch -padding [list 10 5]
		spinbox $top.stretch.spin -from 2048 -to 65535 -increment 256 \
				-justify right -width 8 \
				-textvariable ::gorilla::dpd(keyStretchingIterations)
		ttk::label $top.stretch.label -text [mc "V3 key stretching iterations"]
		pack $top.stretch.spin $top.stretch.label -side left -padx 3
		pack $top.stretch -anchor w -side top

		ttk::separator $top.sep -orient horizontal
		pack $top.sep -side top -fill x -pady 10

		ttk::frame $top.buts
		set but1 [ttk::button $top.buts.b1 -width 15 -text "OK" \
			-command "set ::gorilla::guimutex 1"]
		set but2 [ttk::button $top.buts.b2 -width 15 -text [mc "Cancel"] \
			-command "set ::gorilla::guimutex 2"]
		pack $but1 $but2 -side left -padx 20
		pack $top.buts -side top -pady 10

		bind $top.uni <Return> "set ::gorilla::guimutex 1"
		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyDatabasePreferencesDialog
	} else {
		wm deiconify $top
	}

	set oldGrab [grab current .]

	update idletasks
	raise $top
	focus $top.buts.b1
	catch {grab $top}

	set ::gorilla::guimutex 0
	vwait ::gorilla::guimutex

	if {$oldGrab != ""} {
		catch {grab $oldGrab}
	} else {
		catch {grab release $top}
	}

	wm withdraw $top

	if {$::gorilla::guimutex != 1} {
		return
	}

	set isModified 0

	if {$::gorilla::dpd(IdleTimeout) > 0} {
		set ::gorilla::dpd(LockOnIdleTimeout) 1
	} else {
		set ::gorilla::dpd(LockOnIdleTimeout) 0
	}

	foreach pref {IdleTimeout IsUTF8 LockOnIdleTimeout SaveImmediately} {
		set oldPref [$::gorilla::db getPreference $pref]
		if {![string equal $::gorilla::dpd($pref) $oldPref]} {
			set isModified 1
			$::gorilla::db setPreference $pref $::gorilla::dpd($pref)
		}
	}

	set newVersion $::gorilla::dpd(defaultVersion)

	if {$newVersion != $oldVersion} {
		$::gorilla::db setHeaderField 0 [list $newVersion 0]
		set isModified 1
	}

	$::gorilla::db configure -keyStretchingIterations \
		$::gorilla::dpd(keyStretchingIterations)

	if {$::gorilla::dpd(keyStretchingIterations) != $oldKeyStretchingIterations} {
		set isModified 1
	}

	if {$isModified} {
		MarkDatabaseAsDirty
	}

	ArrangeIdleTimeout
}

# ----------------------------------------------------------------------
# Preferences Dialog
# ----------------------------------------------------------------------
#

proc gorilla::DestroyPreferencesDialog {} {
	set ::gorilla::guimutex 2
}

proc gorilla::PreferencesDialog {} {
	ArrangeIdleTimeout

	set top .preferencesDialog

	foreach {pref default} {
		clearClipboardAfter 0 \
		defaultVersion 3 \
		doubleClickAction nothing \
		exportAsUnicode 0 \
		exportFieldSeparator "," \
		exportIncludeNotes 0 \
		exportIncludePassword 0 \
		exportShowWarning 1 \
		idleTimeoutDefault 5 \
		keepBackupFile 0 \
		lruSize 10 \
		lockDatabaseAfter 0 \
		rememberGeometries 1 \
		saveImmediatelyDefault 0 \
		unicodeSupport 1 \
		lang en \
		fontsize 10 \
		gorillaIcon 0 \
		} {
		if {[info exists ::gorilla::preference($pref)]} {
			set ::gorilla::prefTemp($pref) $::gorilla::preference($pref)
		} else {
			set ::gorilla::prefTemp($pref) $default
		}
	}

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		TryResizeFromPreference $top
		wm title $top [mc "Preferences"]

		ttk::notebook $top.nb

#
# First NoteBook tab: (g)eneral (p)re(f)erences
#

set gpf $top.nb.gpf

$top.nb add [ttk::frame $gpf] -text [mc "General"]

ttk::labelframe $gpf.dca -text [mc "When double clicking a login ..."] \
	-padding [list 5 5]
ttk::radiobutton $gpf.dca.cp -text [mc "Copy password to clipboard"] \
	-variable ::gorilla::prefTemp(doubleClickAction) \
	-value "copyPassword" 
ttk::radiobutton $gpf.dca.ed -text [mc "Edit Login"] \
	-variable ::gorilla::prefTemp(doubleClickAction) \
	-value "editLogin"
ttk::radiobutton $gpf.dca.nop -text [mc "Do nothing"] \
	-variable ::gorilla::prefTemp(doubleClickAction) \
	-value "nothing"
pack $gpf.dca.cp $gpf.dca.ed $gpf.dca.nop -side top -anchor w -pady 3
pack $gpf.dca -side top -padx 10 -pady 5 -fill x -expand yes

ttk::frame $gpf.cc -padding [list 8 5]
ttk::label $gpf.cc.l1 -text [mc "Clear clipboard after"]
spinbox $gpf.cc.s -from 0 -to 999 -increment 1 \
	-justify right -width 4 \
	-textvariable ::gorilla::prefTemp(clearClipboardAfter)
ttk::label $gpf.cc.l2 -text [mc "seconds (0=never)"]
pack $gpf.cc.l1 $gpf.cc.s $gpf.cc.l2 -side left -padx 3
pack $gpf.cc -side top -anchor w

ttk::frame $gpf.lru -padding [list 8 5]
ttk::label $gpf.lru.l1 -text [mc "Remember"]
spinbox $gpf.lru.s -from 0 -to 32 -increment 1 \
	-justify right -width 4 \
	-textvariable ::gorilla::prefTemp(lruSize)
ttk::label $gpf.lru.l2 -text [mc "database names"]
ttk::button $gpf.lru.c -width 10 -text [mc "Clear"] \
	-command "set ::gorilla::guimutex 3"
pack $gpf.lru.l1 $gpf.lru.s $gpf.lru.l2 -side left -padx 3
pack $gpf.lru.c -side right
pack $gpf.lru -side top -anchor w -pady 3 -fill x

ttk::checkbutton $gpf.bu -text [mc "Backup database on save"] \
	-variable ::gorilla::prefTemp(keepBackupFile)
ttk::checkbutton $gpf.geo -text [mc "Remember sizes of dialog boxes"] \
	-variable ::gorilla::prefTemp(rememberGeometries)
pack $gpf.bu $gpf.geo -side top -anchor w -padx 10 -pady 5

#
# Second NoteBook tab: database defaults
#

set dpf $top.nb.dpf
$top.nb add [ttk::frame $dpf] -text [mc "Defaults"]

ttk::frame $dpf.il -padding [list 10 10]
ttk::label $dpf.il.l1 -text [mc "Lock when idle after"]
spinbox $dpf.il.s -from 0 -to 999 -increment 1 \
		-justify right -width 4 \
		-textvariable ::gorilla::prefTemp(idleTimeoutDefault)
ttk::label $dpf.il.l2 -text [mc "minutes (0=never)"]
pack $dpf.il.l1 $dpf.il.s $dpf.il.l2 -side left -padx 3
pack $dpf.il -side top -anchor w -pady 3

ttk::checkbutton $dpf.si -text [mc "Auto-save database immediately when changed"] \
				-variable ::gorilla::prefTemp(saveImmediatelyDefault)
ttk::checkbutton $dpf.ver -text [mc "Use Password Safe 3 format"] \
		-variable ::gorilla::prefTemp(defaultVersion) \
		-onvalue 3 -offvalue 2
ttk::checkbutton $dpf.uni -text [mc "V2 Unicode support"] \
	-variable ::gorilla::prefTemp(unicodeSupport)

pack $dpf.si $dpf.ver $dpf.uni -side top -anchor w -pady 3 -padx 10

ttk::label $dpf.note -justify center -anchor w -wraplen 300 \
	-text [mc "Note: these defaults will be applied to\
	new databases. To change a setting for an existing\
	database, go to \"Customize\" in the \"Security\"\
	menu."]
pack $dpf.note -side bottom -anchor center -pady 3

#
# Third NoteBook tab: export preferences
#

set epf $top.nb.epf
$top.nb add [ttk::frame $epf -padding [list 10 10]] -text [mc "Export"]

ttk::checkbutton $epf.password -text [mc "Include password field"] \
		-variable ::gorilla::prefTemp(exportIncludePassword)
ttk::checkbutton $epf.notes -text [mc "Include \"Notes\" field"] \
		-variable ::gorilla::prefTemp(exportIncludeNotes) 
ttk::checkbutton $epf.unicode -text [mc "Save as Unicode text file"] \
		-variable ::gorilla::prefTemp(exportAsUnicode) 
		
ttk::frame $epf.fs
ttk::label $epf.fs.l -text [mc "Field separator"] -width 16 -anchor w
ttk::entry $epf.fs.e	 \
		-textvariable ::gorilla::prefTemp(exportFieldSeparator) \
	 -width 4 
pack $epf.fs.l $epf.fs.e -side left
ttk::checkbutton $epf.warning -text [mc "Show security warning"] \
		-variable ::gorilla::prefTemp(exportShowWarning) 
		
pack $epf.password $epf.notes $epf.unicode $epf.warning $epf.fs \
	-anchor w -side top -pady 3

		#
		# Fourth NoteBook tab: Display
		#
		
		set languages [gorilla::getAvailableLanguages]
		# format: {en English de Deutsch ...}
		# Fehlerabfrage für falschen prefTemp(lang) Eintrag in der gorillarc
		if {[lsearch $languages $::gorilla::prefTemp(lang)] == -1} {
			set ::gorilla::prefTemp(lang) en
		}
		set ::gorilla::fullLangName [dict get $languages $::gorilla::prefTemp(lang)]
		
		set display $top.nb.display
		$top.nb add [ttk::frame $display -padding [list 10 10]] -text [mc "Display"]
		
		ttk::frame $display.lang -padding {10 10}
		ttk::label $display.lang.label -text [mc "Language:"] -width 9
		ttk::menubutton $display.lang.mb -textvariable ::gorilla::fullLangName \
			-width 8 -direction right
		set m [menu $display.lang.mb.menu -tearoff 0]
		$display.lang.mb configure -menu $m
		
		foreach {lang name} $languages {
			$m add radio -label $name -variable ::gorilla::prefTemp(lang) -value $lang \
				-command "set ::gorilla::fullLangName $name"
		}
		
		pack $display.lang.label $display.lang.mb -side left
		pack $display.lang -anchor w
		
		# font options
		
		ttk::frame $display.size -padding {10 10}
		ttk::label $display.size.label -text [mc "Size:"] -width 9
		ttk::menubutton $display.size.mb -textvariable ::gorilla::prefTemp(fontsize) \
			-width 8 -direction right
		set m [menu $display.size.mb.menu -tearoff 0]
		$display.size.mb configure -menu $m
		
		set sizes "8 9 10 11 12 14 16"
		foreach {size} $sizes {
			$m add radio -label $size -variable ::gorilla::prefTemp(fontsize) -value $size \
				-command "
					font configure TkDefaultFont -size $size
					font configure TkTextFont -size $size
					font configure TkMenuFont -size $size
					ttk::style configure gorilla.Treeview -rowheight [expr {$size * 2}]"
		}
		
		pack $display.size.label $display.size.mb -side left
		pack $display.size -anchor w
		
		# gorilla icon in OpenDatabase
		
		ttk::frame $display.icon -padding {10 10}
		ttk::label $display.icon.label -text [mc "Show Gorilla Icon"]
		ttk::checkbutton $display.icon.check -variable ::gorilla::prefTemp(gorillaIcon) 
		
		pack $display.icon.label -side left
		pack $display.icon.check -padx 10
		pack $display.icon -anchor w
		
		#
		# End of NoteBook tabs
		#

		# $top.nb compute_size
		# $top.nb raise gpf
		pack $top.nb -side top -fill both -expand yes -pady 10

#
# Bottom
#

# Separator $top.sep -orient horizontal
# pack $top.sep -side top -fill x -pady 7

frame $top.buts
set but1 [ttk::button $top.buts.b1 -width 15 -text "OK" \
	-command "set ::gorilla::guimutex 1"]
set but2 [ttk::button $top.buts.b2 -width 15 -text [mc "Cancel"] \
	-command "set ::gorilla::guimutex 2"]
pack $but1 $but2 -side left -pady 10 -padx 20
pack $top.buts -side top -pady 10 -fill both

set ::gorilla::toplevel($top) $top
wm protocol $top WM_DELETE_WINDOW gorilla::DestroyPreferencesDialog
	} else {
wm deiconify $top
	}

	set oldGrab [grab current .]

	update idletasks
	raise $top
	focus $top.buts.b1
	catch {grab $top}

	while {42} {
ArrangeIdleTimeout
set ::gorilla::guimutex 0
vwait ::gorilla::guimutex

if {$::gorilla::guimutex == 1} {
		break
} elseif {$::gorilla::guimutex == 2} {
		break
} elseif {$::gorilla::guimutex == 3} {
		set ::gorilla::preference(lru) [list]
		set ::gorilla::status [mc "History deleted. After a restart the list will be empty."]
}
	}

	if {$oldGrab != ""} {
		catch {grab $oldGrab}
	} else {
		catch {grab release $top}
	}

	wm withdraw $top

	if {$gorilla::guimutex != 1} {
return
	}

	foreach pref {clearClipboardAfter \
		defaultVersion \
		doubleClickAction \
		exportAsUnicode \
		exportFieldSeparator \
		exportIncludeNotes \
		exportIncludePassword \
		exportShowWarning \
		idleTimeoutDefault \
		keepBackupFile \
		lruSize \
		rememberGeometries \
		saveImmediatelyDefault \
		unicodeSupport 
		lang \
		fontsize \
		gorillaIcon \
		} {
		set ::gorilla::preference($pref) $::gorilla::prefTemp($pref)
	}
}

proc gorilla::Preferences {} {
	gorilla::PreferencesDialog
}


# ----------------------------------------------------------------------
# Save Preferences
# ----------------------------------------------------------------------
#

# Results:
# 	returns 1 if platform is Windows and registry save was successful
#		returns 0 if platform is Mac or Linux doing nothing 
proc gorilla::SavePreferencesToRegistry {} {
	if {![info exists ::tcl_platform(platform)] || \
		$::tcl_platform(platform) != "windows" || \
		[catch {package require registry}]} {
		return 0
	}

	set key {HKEY_CURRENT_USER\Software\FPX\Password Gorilla}

		if {![regexp {Revision: ([0-9.]+)} $::gorillaVersion dummy revision]} {
	set revision "<unknown>"
		}

		registry set $key revision $revision sz

		#
		# Note: findInText omitted on purpose. It might contain a password.
		#

		foreach {pref type} {caseSensitiveFind dword \
			clearClipboardAfter dword \
			defaultVersion dword \
			doubleClickAction sz \
			exportAsUnicode dword \
			exportFieldSeparator sz \
			exportIncludeNotes dword \
			exportIncludePassword dword \
			exportShowWarning dword \
			findInAny dword \
			findInNotes dword \
			findInPassword dword \
			findInTitle dword \
			findInURL dword \
			findInUsername dword \
			idleTimeoutDefault dword \
			keepBackupFile dword \
			lruSize dword \
			rememberGeometries dword \
			saveImmediatelyDefault dword \
			unicodeSupport dword} {
	if {[info exists ::gorilla::preference($pref)]} {
			registry set $key $pref $::gorilla::preference($pref) $type
	}
		}

		if {[info exists ::gorilla::preference(lru)]} {
	if {[info exists ::gorilla::preference(lruSize)]} {
			set lruSize $::gorilla::preference(lruSize)
	} else {
			set lruSize 10
	}

	if {[llength $::gorilla::preference(lru)] > $lruSize} {
			set lru [lrange $::gorilla::preference(lru) 0 [expr {$lruSize-1}]]
	} else {
			set lru $::gorilla::preference(lru)
	}

	registry set $key lru $lru multi_sz
		}

		if {![info exists ::gorilla::preference(rememberGeometries)] || \
			$::gorilla::preference(rememberGeometries)} {
	foreach top [array names ::gorilla::toplevel] {
			if {[scan [wm geometry $top] "%dx%d" width height] == 2} {
		registry set $key "geometry,$top" "${width}x${height}"
			}
	}
		} elseif {[info exists ::gorilla::preference(rememberGeometries)] && \
			!$::gorilla::preference(rememberGeometries)} {
	foreach value [registry values $key geometry,*] {
			registry delete $key $value
	}
		}

		return 1
}

proc gorilla::SavePreferencesToRCFile {} {
	if {[info exists ::gorilla::preference(rc)]} {
		set fileName $::gorilla::preference(rc)
	} else {
		if {[info exists ::env(HOME)] && [file isdirectory $::env(HOME)]} {
			set homeDir $::env(HOME)
		} else {
			set homeDir "~"
		}

		#
		# On the Mac, use $HOME/Library/Preferences/gorilla.rc
		# Elsewhere, use $HOME/.gorillarc
		#

		if {[tk windowingsystem] == "aqua" && \
		[file isdirectory [file join $homeDir "Library" "Preferences"]]} {
			set fileName [file join $homeDir "Library" "Preferences" "gorilla.rc"]
		} else {
			set fileName [file join $homeDir ".gorillarc"]
		}
	}

	if { [catch {set f [open $fileName "w"]}] } {
		return 0
	}

	if {![regexp {Revision: ([0-9.]+)} $::gorillaVersion dummy revision]} {
		set revision "<unknown>"
	}

	puts $f "revision=$revision"

		#
		# Note: findInText omitted on purpose. It might contain a password.
		#

	foreach pref {caseSensitiveFind \
			clearClipboardAfter \
			defaultVersion \
			doubleClickAction \
			exportAsUnicode \
			exportIncludeNotes \
			exportIncludePassword \
			exportShowWarning \
			findInAny \
			findInNotes \
			findInPassword \
			findInTitle \
			findInURL \
			findInUsername \
			idleTimeoutDefault \
			keepBackupFile \
			lruSize \
			rememberGeometries \
			saveImmediatelyDefault \
			unicodeSupport \
			lang \
			fontsize \
			gorillaIcon \
			} {
		if {[info exists ::gorilla::preference($pref)]} {
			puts $f "$pref=$::gorilla::preference($pref)"
		}
	}

	if {[info exists ::gorilla::preference(exportFieldSeparator)]} {
		puts $f "exportFieldSeparator=\"[string map {\t \\t} $::gorilla::preference(exportFieldSeparator)]\""
	}

	if {[info exists ::gorilla::preference(lru)]} {
		if {[info exists ::gorilla::preference(lruSize)]} {
			set lruSize $::gorilla::preference(lruSize)
		} else {
			set lruSize 10
		}

		if {[llength $::gorilla::preference(lru)] > $lruSize} {
			set lru [lrange $::gorilla::preference(lru) 0 [expr {$lruSize-1}]]
		} else {
			set lru $::gorilla::preference(lru)
		}

		foreach file $lru {
			puts $f "lru=\"[string map {\\ \\\\ \" \\\"} $file]\""
		}
	}

	if {![info exists ::gorilla::preference(rememberGeometries)] || \
			$::gorilla::preference(rememberGeometries)} {
		foreach top [array names ::gorilla::toplevel] {
			if {[scan [wm geometry $top] "%dx%d" width height] == 2} {
				puts $f "geometry,$top=${width}x${height}"
			}
		}
	}

	if {[catch {close $f}]} {
		gorilla::msg "Error while saving RC-File"
		return 0
	}
	return 1
}

proc gorilla::SavePreferences {} {
	if {[info exists ::gorilla::preference(norc)] && $::gorilla::preference(norc)} {
		return 0
	}
	SavePreferencesToRCFile
	return 1
}

# ----------------------------------------------------------------------
# Load Preferences
# ----------------------------------------------------------------------
#

proc gorilla::LoadPreferencesFromRegistry {} {
		if {![info exists ::tcl_platform(platform)] || \
			$::tcl_platform(platform) != "windows" || \
			[catch {package require registry}]} {
	return 0
		}

		set key {HKEY_CURRENT_USER\Software\FPX\Password Gorilla}

		if {[catch {registry values $key}]} {
	return 0
		}

		if {![regexp {Revision: ([0-9.]+)} $::gorillaVersion dummy revision]} {
	set revision "<unmatchable>"
		}

		if {[llength [registry values $key revision]] == 1} {
	set prefsRevision [registry get $key revision]
		} else {
	set prefsRevision "<unknown>"
		}

		if {[llength [registry values $key lru]] == 1} {
	set ::gorilla::preference(lru) [registry get $key lru]
		}

		foreach {pref type} {caseSensitiveFind boolean \
			clearClipboardAfter integer \
			defaultVersion integer \
			doubleClickAction ascii \
			exportAsUnicode boolean \
			exportFieldSeparator ascii \
			exportIncludeNotes boolean \
			exportIncludePassword boolean \
			exportShowWarning boolean \
			findInAny boolean \
			findInNotes boolean \
			findInPassword boolean \
			findInTitle boolean \
			findInURL boolean \
			findInUsername boolean \
			findThisText ascii \
			idleTimeoutDefault integer \
			keepBackupFile boolean \
			lruSize integer \
			rememberGeometries boolean \
			saveImmediatelyDefault boolean \
			unicodeSupport integer} {
	if {[llength [registry values $key $pref]] == 1} {
			set value [registry get $key $pref]
			if {[string is $type $value]} {
		set ::gorilla::preference($pref) $value
			}
	}
		}

		if {[info exists ::gorilla::preference(rememberGeometries)] && \
			$::gorilla::preference(rememberGeometries)} {
	foreach value [registry values $key geometry,*] {
			set data [registry get $key $value]
			if {[scan $data "%dx%d" width height] == 2} {
		set ::gorilla::preference($value) "${width}x${height}"
			}
	}
		}

		#
		# If the revision numbers of our preferences don't match, forget
		# about window geometries, as they might have changed.
		#

		if {![string equal $revision $prefsRevision]} {
	foreach geo [array names ::gorilla::preference geometry,*] {
			unset ::gorilla::preference($geo)
	}
		}

		return 1
}

proc gorilla::LoadPreferencesFromRCFile {} {
	if {[info exists ::gorilla::preference(rc)]} {
		set fileName $::gorilla::preference(rc)
	} else {
		if {[info exists ::env(HOME)] && [file isdirectory $::env(HOME)]} {
			set homeDir $::env(HOME)
		} else {
			set homeDir "~"
		}

	#
	# On the Mac, use $HOME/Library/Preferences/gorilla.rc
	# Elsewhere, use $HOME/.gorillarc
	#

	if {[tk windowingsystem] == "aqua" && \
		[file isdirectory [file join $homeDir "Library" "Preferences"]]} {
			set fileName [file join $homeDir "Library" "Preferences" "gorilla.rc"]
	} else {
			set fileName [file join $homeDir ".gorillarc"]
	}
		}

		if {![regexp {Revision: ([0-9.]+)} $::gorillaVersion dummy revision]} {
	set revision "<unmatchable>"
		}

		set prefsRevision "<unknown>"

		if {[catch {
	set f [open $fileName]
		}]} {
	return 0
		}

		while {![eof $f]} {
	set line [string trim [gets $f]]
	if {[string index $line 0] == "#"} {
			continue
	}

	if {[set index [string first "=" $line]] < 1} {
			continue
	}

	set pref [string trim [string range $line 0 [expr {$index-1}]]]
	set value [string trim [string range $line [expr {$index+1}] end]]

	if {[string index $value 0] == "\""} {
			set i 1
			set prefValue ""

			while {$i < [string length $value]} {
		set c [string index $value $i]
		if {$c == "\\"} {
				set c [string index $value [incr i]]
				switch -exact -- $c {
			t {
					set d "\t"
			}
			default {
					set d $c
			}
				}
				append prefValue $c
		} elseif {$c == "\""} {
				break
		} else {
				append prefValue $c
		}
		incr i
			}

			set value $prefValue
	}

	switch -glob -- $pref {
			clearClipboardAfter -
			defaultVersion {
		if {[string is integer $value]} {
				if {$value >= 0} {
			set ::gorilla::preference($pref) $value
				}
		}
			}
			doubleClickAction {
		set ::gorilla::preference($pref) $value
			}
			caseSensitiveFind -
			exportAsUnicode -
			exportIncludeNotes -
			exportIncludePassword -
			exportShowWarning -
			findInAny -
			findInNotes -
			findInPassword -
			findInTitle -
			findInURL -
			findInUsername {
		if {[string is boolean $value]} {
				set ::gorilla::preference($pref) $value
		}
			}
			exportFieldSeparator {
		if {[string length $value] == 1 && \
			$value != "\"" && $value != "\\"} {
				set ::gorilla::preference($pref) $value
		}
			}
			findThisText {
		set ::gorilla::preference($pref) $value
			}
			idleTimeoutDefault {
		if {[string is integer $value]} {
				if {$value >= 0} {
			set ::gorilla::preference($pref) $value
				}
		}
			}
			keepBackupFile {
		if {[string is boolean $value]} {
				set ::gorilla::preference($pref) $value
		}
			}
			lru {
		if { [ file exists $value ] } { 
			lappend ::gorilla::preference($pref) $value
		}
			}
			lruSize {
		if {[string is integer $value]} {
				set ::gorilla::preference($pref) $value
		}
			}
			rememberGeometries {
		if {[string is boolean $value]} {
			set ::gorilla::preference($pref) $value
		}
			}
			revision {
		set prefsRevision $value
			}
			saveImmediatelyDefault {
		if {[string is boolean $value]} {
				set ::gorilla::preference($pref) $value
		}
			}
			unicodeSupport {
		if {[string is integer $value]} {
				set ::gorilla::preference($pref) $value
		}
			}
			geometry,* {
				if {[scan $value "%dx%d" width height] == 2} {
						set ::gorilla::preference($pref) "${width}x${height}"
				}
			}
			lang {
				set ::gorilla::preference($pref) $value
				mclocale $value
				mcload [file join $::gorillaDir msgs]
			}
			fontsize {
				set ::gorilla::preference($pref) $value
				font configure TkDefaultFont -size $value
				font configure TkTextFont -size $value
				font configure TkMenuFont -size $value
				# undocumented option for ttk::treeview
				ttk::style configure gorilla.Treeview -rowheight [expr {$value * 2}]
			}
			gorillaIcon {
				set ::gorilla::preference($pref) $value
			}
	}
		}

		#
		# If the revision numbers of our preferences don't match, forget
		# about window geometries, as they might have changed.
		#

		if {![string equal $revision $prefsRevision]} {
	foreach geo [array names ::gorilla::preference geometry,*] {
			unset ::gorilla::preference($geo)
	}
		}

		catch {close $f}
		return 1
}

proc gorilla::LoadPreferences {} {
	if {[info exists ::gorilla::preference(norc)] && \
		$::gorilla::preference(norc)} {
		return 0
	}
	LoadPreferencesFromRCFile
	return 1
}

# ----------------------------------------------------------------------
# Change the password
# ----------------------------------------------------------------------
#

proc gorilla::ChangePassword {} {
	ArrangeIdleTimeout

	if {![info exists ::gorilla::db]} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "No Database" \
			-message "Please create a new database, or open an existing\
			database first."
		return
	}

	if {[catch {set currentPassword [GetPassword 0 [mc "Current Master Password:"]]} err]} {
		# canceled
		return
	}
	if {![$::gorilla::db checkPassword $currentPassword]} {
		tk_messageBox -parent . \
			-type ok -icon error -default ok \
			-title "Wrong Password" \
			-message "That password is not correct."
		return
	}

	pwsafe::int::randomizeVar currentPassword

	if {[catch {set newPassword [GetPassword 1 [mc "New Master Password:"]] } err]} {
		tk_messageBox -parent . \
			-type ok -icon info -default ok \
			-title "Password Not Changed" \
			-message "You canceled the setting of a new password.\
			Therefore, the existing password remains in effect."
		return
	}
	$::gorilla::db setPassword $newPassword
	pwsafe::int::randomizeVar newPassword
	set ::gorilla::status [mc "Master password changed."]
	MarkDatabaseAsDirty
}

# ----------------------------------------------------------------------
# X Selection Handler
# ----------------------------------------------------------------------
#

proc gorilla::XSelectionHandler {offset maxChars} {
	switch -- $::gorilla::activeSelection {
	0 {
			set data ""
		}
	1 {
			set data [gorilla::GetSelectedUsername]
		}
	2 {
			set data [gorilla::GetSelectedPassword]
		}
	3 {
			set data [gorilla::GetSelectedURL]
		}
	default {
			set data ""
		}
	}

	return [string range $data $offset [expr {$offset+$maxChars-1}]]
}

# ----------------------------------------------------------------------
# Copy the URL to the Clipboard
# ----------------------------------------------------------------------
#

proc gorilla::GetSelectedURL {} {
	if {[catch {set rn [gorilla::GetSelectedRecord]}]} {
		return
	}

		#
		# Password Safe v3 has a dedicated URL field.
		#

	if {[$::gorilla::db existsField $rn 13]} {
		return [$::gorilla::db getFieldValue $rn 13]
	}

		#
		# Password Safe v2 kept the URL in the "Notes" field.
		#

	if {![$::gorilla::db existsField $rn 5]} {
		return
	}

	set notes [$::gorilla::db getFieldValue $rn 5]
	if {[set index [string first "url:" $notes]] != -1} {
		incr index 4
		while {$index < [string length $notes] && \
			[string is space [string index $notes $index]]} {
			incr index
		}
		if {[string index $notes $index] == "\""} {
			incr index
			set URL ""
			while {$index < [string length $notes]} {
				set c [string index $notes $index]
				if {$c == "\\"} {
					append URL [string index $notes [incr index]]
				} elseif {$c == "\""} {
					break
				} else {
					append URL $c
				}
				incr index
			}
		} else {
			if {![regexp -start $index -- {\s*(\S+)} $notes dummy URL]} {
				set URL ""
			}
		}
	} elseif {![regexp -nocase -- {http(s)?://\S*} $notes URL]} {
		set URL ""
	}

	return $URL
}


# ----------------------------------------------------------------------
# Copy the Password to the Clipboard
# ----------------------------------------------------------------------
#

proc gorilla::GetSelectedPassword {} {
	if {[catch {set rn [gorilla::GetSelectedRecord]} err]} {
		return
	}
	if {![$::gorilla::db existsField $rn 6]} {
		return
	}

	return [$::gorilla::db getFieldValue $rn 6]
}

proc gorilla::CopyPassword {} {
	ArrangeIdleTimeout
	clipboard clear
	clipboard append -- [::gorilla::GetSelectedPassword]
	set ::gorilla::activeSelection 2
	selection clear
	selection own .
	ArrangeToClearClipboard
	set ::gorilla::status [mc "Copied password to clipboard."]
}

# ----------------------------------------------------------------------
# Copy the Username to the Clipboard
# ----------------------------------------------------------------------
#

proc gorilla::GetSelectedRecord {} {
	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		error "oops"
	}
	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]
	if {$type != "Login"} {
		error "oops"
	}

	return [lindex $data 1]
}

proc gorilla::GetSelectedUsername {} {
	if {[catch {set rn [gorilla::GetSelectedRecord]}]} {
		return
	}

	if {![$::gorilla::db existsField $rn 6]} {
		return
	}

	return [$::gorilla::db getFieldValue $rn 4]
}

# ----------------------------------------------------------------------
# Miscellaneous
# ----------------------------------------------------------------------
#

proc gorilla::DestroyAboutDialog {} {
		ArrangeIdleTimeout
		set top .about
		catch {destroy $top}
		unset ::gorilla::toplevel($top)
}

proc gorilla::contributors {} {
	# ShowTextFile .help [mc "Using Password Gorilla"] "help.txt"
	tk_messageBox -default ok \
		-message \
		"Gorilla artwork contributed by Andrew J. Sniezek."
}

proc tkAboutDialog {} {
     ##about dialog code goes here
     gorilla::About
} 

proc gorilla::About {} {
	ArrangeIdleTimeout
	set top .about

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		
		set w .about.mainframe
		
		if {![regexp {Revision: ([0-9.]+)} $::gorillaVersion dummy revision]} {
			set revision "<unknown>"
		}
		
		ttk::frame $w -padding {10 10}
		ttk::label $w.image -image $::gorilla::images(splash)
		ttk::label $w.title -text "Password Gorilla $revision" \
			-font {sans 16 bold} -padding {10 10}
		ttk::label $w.description -text "Gorilla will protect your passwords and help you \
		to manage them with a pwsafe 3.2 compatible database" -wraplength 350 -padding {10 0}
		ttk::label $w.copyright \
			-text "(c) 2004-2009 Frank Pillhofer  (c) 2010 Zbigniew Diaczyszyn" \
			-font {sans 8} -padding {10 0}
		ttk::label $w.url -text "http:/github.com/zdia/gorilla" -foreground blue \
			-font {sans 9}
		
		ttk::frame $w.buttons
		ttk::button $w.buttons.contrib -text [mc "Contributors"] -command gorilla::contributors
		ttk::button $w.buttons.license -text [mc License] -command gorilla::License
		ttk::button $w.buttons.close -text [mc "Close"] -command gorilla::DestroyAboutDialog
		
					
		pack $w.image -side top
		pack $w.title -side top -pady 5
		pack $w.description -side top
		pack $w.copyright -side top -pady 5 -fill x
		pack $w.url -side top -pady 5 
		pack $w.buttons.contrib $w.buttons.license $w.buttons.close \
			-side left -padx 5
		pack $w.buttons -side bottom -pady 10
		pack $w
		
		wm title $top [mc "About Password Gorilla"]

		
		bind $top <Return> "gorilla::DestroyAboutDialog"
	
		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW gorilla::DestroyAboutDialog
	} else {
		set w "$top.mainframe"
	}
	
			update idletasks
			wm deiconify $top
			raise $top
			focus $w.buttons.close
			wm resizable $top 0 0
}

proc gorilla::Help {} {
		ArrangeIdleTimeout
		ShowTextFile .help [mc "Using Password Gorilla"] "help.txt"
}

proc gorilla::License {} {
		ArrangeIdleTimeout
		ShowTextFile .license [mc "Password Gorilla License"] "LICENSE.txt"
}

proc gorilla::DestroyTextFileDialog {top} {
		ArrangeIdleTimeout
		catch {destroy $top}
		unset ::gorilla::toplevel($top)
}

proc gorilla::ShowTextFile {top title fileName} {
	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top

		wm title $top $title

		set text [text $top.text -relief sunken -width 80 \
			-yscrollcommand "$top.vsb set"]

		if {[tk windowingsystem] ne "aqua"} {
			ttk::scrollbar $top.vsb -orient vertical -command "$top.text yview"
		} else {
			scrollbar $top.vsb -orient vertical -command "$top.text yview"
		}

		## Arrange the tree and its scrollbars in the toplevel
		lower [ttk::frame $top.dummy]
		pack $top.dummy -fill both -fill both -expand 1
		grid $top.text $top.vsb -sticky nsew -in $top.dummy
		grid columnconfigure $top.dummy 0 -weight 1
		grid rowconfigure $top.dummy 0 -weight 1

		set botframe [ttk::frame $top.botframe]
		set botbut [ttk::button $botframe.but -width 10 -text [mc "Close"] \
				-command "gorilla::DestroyTextFileDialog $top"]
		pack $botbut
		pack $botframe -side top -fill x -pady 10

		bind $top <Prior> "$text yview scroll -1 pages; break"
		bind $top <Next> "$text yview scroll 1 pages; break"
		bind $top <Up> "$text yview scroll -1 units"
		bind $top <Down> "$text yview scroll 1 units"
		bind $top <Home> "$text yview moveto 0"
		bind $top <End> "$text yview moveto 1"
		bind $top <Return> "gorilla::DestroyTextFileDialog $top"

		$text configure -state normal
		$text delete 1.0 end

		set filename [file join $::gorillaDir $fileName]
		if {[catch {
				set file [open $filename]
				$text insert 1.0 [read $file]
				close $file}]} {
			$text insert 1.0 "Oops: file not found: $fileName"
		}

		$text configure -state disabled

		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW "gorilla::DestroyTextFileDialog $top"
	} else {
		set botframe "$top.botframe"
	}

	update idletasks
	wm deiconify $top
	raise $top
	focus $botframe.but
	wm resizable $top 0 0
}

# ----------------------------------------------------------------------
# Find
# ----------------------------------------------------------------------
#

proc gorilla::CloseFindDialog {} {
	set top .findDialog
	if {[info exists ::gorilla::toplevel($top)]} {
		wm withdraw $top
	}
}

proc gorilla::Find {} {
	ArrangeIdleTimeout

	if {![info exists ::gorilla::db]} {
		return
	}

	set top .findDialog

	foreach {pref default} {
		caseSensitiveFind 0
		findInAny 0
		findInTitle 1
		findInUsername 1
		findInPassword 0
		findInNotes 1
		findInURL 1
		findThisText ""
			} {
		if {![info exists ::gorilla::preference($pref)]} {
			set ::gorilla::preference($pref) $default
		}
	}

	if {![info exists ::gorilla::toplevel($top)]} {
		toplevel $top
		TryResizeFromPreference $top
		wm title $top "Find"

		ttk::frame $top.text -padding [list 10 10]
		ttk::label $top.text.l -text [mc "Find Text:"] -anchor w -width 10
		ttk::entry $top.text.e -width 40 \
				-textvariable ::gorilla::preference(findThisText)
		pack $top.text.l $top.text.e -side left
		
		ttk::labelframe $top.find -text [mc "Find Options ..."] \
			-padding [list 10 10]
		ttk::checkbutton $top.find.any -text [mc "Any field"] \
				-variable ::gorilla::preference(findInAny)
		ttk::checkbutton $top.find.title -text [mc "Title"] -width 10 \
				-variable ::gorilla::preference(findInTitle)
		ttk::checkbutton $top.find.username -text [mc "Username"] \
				-variable ::gorilla::preference(findInUsername)
		ttk::checkbutton $top.find.password -text [mc "Password"] \
				-variable ::gorilla::preference(findInPassword)
		ttk::checkbutton $top.find.notes -text [mc "Notes"] \
				-variable ::gorilla::preference(findInNotes)
		ttk::checkbutton $top.find.url -text "URL" \
				-variable ::gorilla::preference(findInURL)
		ttk::checkbutton $top.find.case -text [mc "Case sensitive find"] \
				-variable ::gorilla::preference(caseSensitiveFind)
		
		grid $top.find.any  $top.find.title $top.find.password -sticky nsew
		grid  ^ $top.find.username $top.find.notes -sticky nsew
		grid  ^  $top.find.url -sticky nsew
		grid $top.find.case -sticky nsew
		
		grid columnconfigure $top.find 0 -weight 1
		
		ttk::frame $top.buts -padding [list 10 10]
		set but1 [ttk::button $top.buts.b1 -width 10 -text [mc "Find"] \
						-command "::gorilla::RunFind"]
		set but2 [ttk::button $top.buts.b2 -width 10 -text [mc "Close"] \
						-command "::gorilla::CloseFindDialog"]
		pack $but1 $but2 -side left -pady 10 -padx 20 -fill x -expand 1
		
		pack $top.buts -side bottom -expand yes -fill x -padx 20 -pady 5
		pack $top.text -side top -expand yes -fill x -pady 5
		pack $top.find -side left -expand yes -fill x -padx 20 -pady 5
		
		bind $top.text.e <Return> "::gorilla::RunFind"


# if any then all checked
# $top.find.case state selected

		bind $top.text.e <Return> "::gorilla::RunFind"

		set ::gorilla::toplevel($top) $top
		
		wm attributes $top -topmost 1
		focus $top.text.e
		update idletasks
		wm protocol $top WM_DELETE_WINDOW gorilla::CloseFindDialog
		
	} else {
		wm deiconify $top
		# Dialog_Wait
	}

	#
	# Start with the currently selected node, if any.
	#

	set selection [$::gorilla::widgets(tree) selection]
	if {[llength $selection] > 0} {
		set ::gorilla::findCurrentNode [lindex $selection 0]
	} else {
		set ::gorilla::findCurrentNode [lindex [$::gorilla::widgets(tree) children {}] 0]
	}
}

proc gorilla::FindNextNode {node} {
	#
	# If this node has children, return the first child.
	#
	set children [$::gorilla::widgets(tree) children $node]

	if {[llength $children] > 0} {
		return [lindex $children 0]
	}

	while {42} {
		#
		# Go to the parent, and find its next child.
		#
		set parent [$::gorilla::widgets(tree) parent $node]
		set children [$::gorilla::widgets(tree) children $parent]
		set indexInParent [$::gorilla::widgets(tree) index $node]
		incr indexInParent
# gets stdin
# break
		if {$indexInParent < [llength $children]} {
				set node [lindex $children $indexInParent]
				break
		}

		#
		# Parent doesn't have any more children. Go up one level.
		#

		set node $parent
		#
		# If we are at the root node, return its first child (wrap around).
		#

		if {$node == {} } {
			set node [lindex [$::gorilla::widgets(tree) children {}] 0]
			break
		}

		#
		# Find the parent's next sibling (Geschwister)
		#
	} ;# end while
	return $node
}

proc gorilla::FindCompare {needle haystack caseSensitive} {
		if {$caseSensitive} {
	set cmp [string first $needle $haystack]
		} else {
	set cmp [string first [string tolower $needle] [string tolower $haystack]]
		}

		return [expr {($cmp == -1) ? 0 : 1}]
}

proc gorilla::RunFind {} {
	if {![info exists ::gorilla::findCurrentNode]} {
		set ::gorilla::findCurrentNode [lindex [$::gorilla::widgets(tree) children {}] 0]
	} else {
		set ::gorilla::findCurrentNode [::gorilla::FindNextNode $::gorilla::findCurrentNode]
	}
	
	set text $::gorilla::preference(findThisText)
	set node $::gorilla::findCurrentNode

	set found 0
	set recordsSearched 0
	set totalRecords [llength [$::gorilla::db getAllRecordNumbers]]
	
 	while {!$found} {
# puts "\n--- Runfind while-schleife: next node is $node"

		# set node [::gorilla::FindNextNode $node]
		
		set data [$::gorilla::widgets(tree) item $node -values]
		set type [lindex $data 0]


		
		if {$type == "Group" || $type == "Root"} {
			set node [::gorilla::FindNextNode $node]
			if {$node == $::gorilla::findCurrentNode} {
				break
			}
			continue
		}
		
		incr recordsSearched
		set percent [expr {int(100.*$recordsSearched/$totalRecords)}]
		set ::gorilla::status "Searching ... ${percent}%"
		update idletasks

		set rn [lindex $data 1]
		set fa $::gorilla::preference(findInAny)
		set cs $::gorilla::preference(caseSensitiveFind)
		if {($fa || $::gorilla::preference(findInTitle)) && \
			[$::gorilla::db existsField $rn 3]} {
				if {[FindCompare $text [$::gorilla::db getFieldValue $rn 3] $cs]} {
					set found 3
					break
				}
		}

		if {($fa || $::gorilla::preference(findInUsername)) && \
			[$::gorilla::db existsField $rn 4]} {
				if {[FindCompare $text [$::gorilla::db getFieldValue $rn 4] $cs]} {
			set found 4
			break
				}
		}

		if {($fa || $::gorilla::preference(findInPassword)) && \
			[$::gorilla::db existsField $rn 6]} {
				if {[FindCompare $text [$::gorilla::db getFieldValue $rn 6] $cs]} {
			set found 6
			break
				}
		}

		if {($fa || $::gorilla::preference(findInNotes)) && \
			[$::gorilla::db existsField $rn 5]} {
				if {[FindCompare $text [$::gorilla::db getFieldValue $rn 5] $cs]} {
			set found 5
			break
				}
		}

		if {($fa || $::gorilla::preference(findInURL)) && \
			[$::gorilla::db existsField $rn 13]} {
				if {[FindCompare $text [$::gorilla::db getFieldValue $rn 13] $cs]} {
			set found 13
			break
				}
		}

		set node [::gorilla::FindNextNode $node]
		
		if {$node == $::gorilla::findCurrentNode} {
			#
			# Wrapped around.
			#
			break
		}
	} ;# end while loop

	if {!$found} {
		set ::gorilla::status [mc "Text not found."]
		return
	}
	#
	# Text found.
	#

	#
	# Make sure that all of node's parents are open.
	#

	set parent [$::gorilla::widgets(tree) parent $node]

	while {$parent != "RootNode"} {
		$::gorilla::widgets(tree) item $parent -open 1
		set parent [$::gorilla::widgets(tree) parent $parent]
			}

			#
			# Make sure that the node is visible.
			#

			$::gorilla::widgets(tree) see $node
			$::gorilla::widgets(tree) selection set $node

			#
			# Report.
			#

		switch -- $found {
	3 {
			set ::gorilla::status "Found matching title."
	}
	4 {
			set ::gorilla::status "Found matching username."
	}
	5 {
			set ::gorilla::status "Found matching notes."
	}
	6 {
			set ::gorilla::status "Found matching password."
	}
	13 {
			set ::gorilla::status "Found matching URL."
	}
	default {
			set ::gorilla::status "Found match."
	}
		}

		#
		# Remember.
		#

		set ::gorilla::findCurrentNode $node
}

proc gorilla::FindNext {} {
	set ::gorilla::findCurrentNode [::gorilla::FindNextNode $::gorilla::findCurrentNode]
	gorilla::RunFind
}

proc gorilla::getAvailableLanguages {  } {
	set files [glob -tail -path "$::gorillaDir/msgs/" *.msg]
	set msgList "en"
	
	foreach file $files {
		lappend msgList [lindex [split $file "."] 0]
	}
	
	# Diese Liste muss erweitert werden, vgl. "locale -a"
	set langFullName [list en English de Deutsch fr Français es Espagnol ru Russian]
	
	# erstelle Liste mit {locale fullname}
	set langList {}
	foreach lang $msgList {
		set res [lsearch $langFullName $lang]
		lappend langList [lindex $langFullName $res] [lindex $langFullName [incr res]]
	}
	return $langList
}

# ----------------------------------------------------------------------
# Icons
# ----------------------------------------------------------------------
#

set ::gorilla::images(application) [image create photo -data "
R0lGODlhEAAQAMZxAF4qAl4rAWAtAmEuBmMvAWQwAGIwCmMxCmU0DWk4DGs5DW87AGw7DXA8AW88
BGw8EGw8EnFADnFCHHdFD3dGDn1JA3ZJIX9MBX1ND4VRBIFSGIJSHItZC4RZM49eEoxeH4peKZJh
GYxiNpFkLYxlOZBoP5dqJpRqNZlrIJ1uG6V5LKJ5PaJ7RquAK6OBTrCMSriQILmPLraPVbaUYcKZ
SMCaUsqcLdirIsiqdNWtOcmsdNm3UuC5SuzAMeTBVN/DcuzMUPjQI+7OVfjQJvXQNfDOWO3PV/bP
Q/7TKvbUOO/TZfbUVPvYKvzZKvvaJ/jXUfDYePbYZ/bZY/ncRPzcRPnbZ/zgMvjeWf/iJv7iM/ff
df/jOfjhe//nLvbhhP/oNPvkdf/qNP/mZ/rnh/voh/fsqPrtnf7ukvfuqP3wm/nwqPryqfryq/vy
qv70q//1qP32sv///////////////////////////////////////////////////////////yH+
EUNyZWF0ZWQgd2l0aCBHSU1QACH5BAEKAH8ALAAAAAAQABAAAAeXgH+Cg4ISIicgDISLfyVKU0mR
G4yCHVdfWTAHGkkTjAM/YVZNGH8GNkkEixBGXU5BNxQtRTwOiw9AWExER0tVXD4NiwI7W1RPUlpj
ZjkFjC9CYmBkaXBeFYwuazFRZ29uUByMJG0qQzQpKB4LjBZqK0g1H5SCCGgsPReK9ABlMyYZ6AkK
wAbHCIGDEuiQEQLhIAURHAoKBAA7"]

set ::gorilla::images(browse) [image create photo -data "
R0lGODlhFAASAKEBAC5Ecv///5sJCQAAACH5BAEAAAMALAAAAAAUABIAAAJCnI+pywoPowQIBDvj
rbnXAIaiSB1WIAhiSn5oqr7sZo52WBrnDPK03oMFZ7nB6TYq7mLBVk0Wg8WUSJuyk2lot9wCADs=
"]

set ::gorilla::images(group) [image create photo -data "
R0lGODlhDQANAJEAANnZ2QAAAP//AP///yH5BAEAAAAALAAAAAANAA0AAAIyhI+pe0EJ4VuE
iFBC+EGyg2AHyZcAAKBQvgQAAIXyJQh2kOwg+BEiEhTCt4hAREQIHVIAOw==
"]

set ::gorilla::images(login) [image create photo -data "
R0lGODlhDQANAJEAANnZ2QAAAAD/AP///yH5BAEAAAAALAAAAAANAA0AAAI0hI+pS/EPACBI
vgQAAIXyJQAAKJQvAQBAoXwJAAAK5UsAAFAoXwIAgEL5EgAAFP8IPqZuAQA7
"]

set ::gorilla::images(wfpxsm) [image create photo -data "
R0lGODlhfgBEANUAAPr6+v39/f7+/v////Pz8+zs7OTk5Nvb29bW1tLS0s3NzcnJycXFxcHBwb29
vbq6ura2trGxsampqa6urqampqKiop2dnZqampWVlZGRkY2NjYqKioWFhYKCgn19fXp6enV1dXFx
cW1tbWpqamZmZmJiYmFhYV5eXllZWVVVVVJSUk1NTUlJSUZGRkFBQT4+Pjo6OjU1NTIyMi4uLikp
KSYmJiIiIh4eHhoaGhUVFREREQoKCg0NDQUFBQMDAwAAACH5BAkIAAAALAAAAAB+AEQAAAb+wIFw
SCwaj8ikcslsOp/QqHRKrVqv2Kx2y+16v+CweEwum8/otHrNbrvf04SjwWAsFIoEAnHoHwwGfQgJ
CgsMDg8RExEQD3N2eXx+g4UNDhATmZmMjY92d3l6e5OUhpYQiowPdHeifgcFWiEzMS8sKiglIyAf
HRsZGMEZHB8iJysvMzc7Pz88ODQxLSonux4dHR4gJCgsMDU5zc09PDk3NTIwLre5u70cGxoZGhsd
ICPHLso6ztAw0yZCfOCQ4YKFCwq0iLChQ8cNGzZozJBBEQaMFy9caMTIEUaMGBRniKRRowbEGzhy
6OCxQ0cOHDhuyIwocWKMixlbsFihIkX+ChQnTpQgQXSEUaMijiZFKqLpUhIlTqCogEDLiBsuH9aQ
SPEjTo1gw7p4YfGjjBkkbaBUyaOHj5Y5Xs7cKlKG14saW+jcuYJnT58/UQgeLNinisN9W4yFcVZC
1Swkbsila/dmxrx6M2veWPZs2rU6drjl4fJlzIc2ttakWPmuRY6wY1v0aBatSZQre1B4jKVEzBq0
1LXgGVhw3xUsXMCYUQNHw4Y8omdNvbWkWpU7fPjowZ07aRwR070YnuIEiRECfQGzgIGYMRUuYjSP
niNijHXUSAj0YCGBFgsi8HINPPIEE0wHhx3mwgraiECCCRBGCOF5IoQQAggYhpDUgxL+RnjehdfE
g4FBFEigCh2RKMDAAxNQcMEwH4QAlTUcaICBBRRM0MkDB6DRwDQ+xQDCEwUAEsgBlORBgBIAvIJk
LEoUWcCUU8KBhAMxCHbCDCI8cYEHMsInwzI/6FBDChRAWQQBUqGgwgotkBBAEgT0osEFFETwgJVH
PEDDCRDWQMITG6jAUENxTSZDCydIsGQRGIwgQ1zjNZDEBCGoQNEHDxjApxEQ3GBeZCc8AQIMPvzQ
Eg4lcZXOCiZ00CMRBmwT3Q0rnDCnEQQMRYMNMlTgwK6fDjEBD7qIgAMKT5BQww896MAqDXa9htEK
JYSQEBERdPDCS7ZIYIQAHaDgAg3/NJCAgafFEiGBD/qFsOwTKeAQrQ34CaYCC5mtUw27QhCQQQdq
1dDXo0MgsA5ILnhQQbtFSPDDLiDcwKwTLoSGwwwqdKCBNtiEkMKbLNwCAgBEKJBBCltltAERAKRQ
i0UoiAAwxANIvJ8NpTohww71xaCCpwEY8AAwGYww8goa8TYAABVsEMNEL8Qw6wAZ3CBDXilkgLO7
P4BwTbpP0NCDP0MTQcADFlQQgpst0GBBEQhoUMJHyZggwAAHxLUOC7bcjLMEPQzEgQxdOkHDDsC6
kDbdFVxQAgor5GBCEQFYAEILGc2QgwMCnPBDDYe9QMPLXxvLgwcbbABDCGXzUIM0/isILsQDF4xQ
wgo9pGDEASK7oJgOMiwA7QoopFCfmqlPkEONGbDwwROT0mBL7UcskIGMKfzguxEcqKCToT/k0IMM
JpQwQw8apM7tDRsEw+ATMWy8YAu2DxABByCIgMIO3yvCAVoAA1yogDs5IIoJclADhLkPAjaw0QVS
wIEnvOAGM1iQC2yHAA94IEYnyMHFjOCBGrwAUD9bQVNeYIMJuI8IEKBBBixgARSgrgkusMEMhvOC
mwUgAhby4NtuUMEjHMA5o3LBhUbAMWK98AEywEAFKlCC8gzlKCMgygkcQAQWAGdh7FpbCMzjCzCx
gAaWQoIJfoC4C33gAwRM4wtv/heDC1SAAhmIBz1ax4EOfAAEJZDjAFbQshbM4AMbEEHJVAACDMCI
BLZAGRIQEC13gMkFQ5rjEB4AAzwtIgKKkEAF2DMMD4iAAURQAUnUkQ5/cWCKF9CAPVKwgm0loQQ5
aME7aOm0OTrgBRYwEQSGqQgKsEcDHPjgAoiAguZkMAUkQOSILoABZG7jBC5cAgtwsIIOwEMqV9Ok
A1wQzAgchIYHoSYGNsABDthyAM00UwxYUDMQ+IKdydQGKpfAADMN5BccKAEGNDmEH3kyRh6o0Yja
FrkM+GcIJ6jB2ayHPP0MRAP0kADzktACbqpnRH8M5wt/JEUJeIACTzDBs3Yw/wN3fNQCDsjfERrA
Axv8EwR2tEAHLrA3Tf7oThb4AEqdYAIaNMMGImiAKwogySYEYAY66BgHlLaBCkjAkSJN3Y8UCoKh
NqEEZtvBDUKwUShUwAc3sKcHkCeCHEXgAhFoqvt+9I6uPkF9LpkBWakAAKOuQGz7kpEGGJGJrOLM
AS1wowge5oS7PeR1ZXUCBX6AgwCNAAYjIECAJNCICThArl8bJ4VGwNgmmAAG1HqBCCLLBALIQAcr
QA9IEgIBEWhgERKgwEPd90ugQGhuTjhB1f4xAtYuwQK0MA8LbjCCvQEABCHAUQWC4UCccZI4KLjA
E8yllxWQwLh0QgEMkBfCG/5cbQHRpKYGPhCBJ95HLyoYqBNQMJyemAC8SIhACsgTgx4kTggC+MAJ
PLaBEJRApnyCQHD+4TUn7BcogkEwEgogYOEtFwcbRQDyhNjNB6pmBi+4IRP2pcDHPSECIPBGfG4g
XyIE+IQaYoEMelmsCMhEJjLowBNKZiESsEDCRijAVCfCmBeAVggGOEsJJncDFqQuAiqJCw088ATF
jEAEJughFCbQAUOmYwZ7QoIHcjDPFtigBxD42rEmk8kmXDA8MQCy2uwxAsq9AAVOXJP5UrUDHKjg
awXAQwIGLeeEDVoUR04CAAAxCfweAA+RoDEZ5MCKSrDIRTCSkYc+5EYPYv/j09jw4B9DkMUOocdO
N8rTKkCxAAdEANN01oUbvfmLG91xEY2gQx0akAgJsGcD+8RCBNgJjGDI8h75kIEN2EKauMBEKxKx
zGXGUjW02MA5K9lBOW6QWhakwAQB6kAGYIQPpsmgOdIKjzrYYQL0iA1606xmMmUETC1IQMAkCBAv
MuSgydGSc1OrgWSyIw4d6PAfyGt3hTSkOzsrmx/iiDi04BKT1NhEODvBBaA+hKEB1dogt1bFC7Sb
BQpsYz/exMaoG74v5ciABpJpizgYKIMXrODblvRg/6roDRqEQ+LN2E6zf8OVWggPu0Lh+AdCVCA7
lgjXWCI5FtyWHj2y84PJpDaBm5LDmF/FvDsY/Ac1XNrObGyjG6jFgXa20x1yuKTilKlWRjIOFPO4
e+nebHrbns6IGbT4CrlzSqkpF5/mMANa2wZOLeoLlKIIngQnoGXhccADcfiAB9y+D/JkbaERmGC/
8jGfOMhhDuC0cic/AdSSo7L1qjWnfVl4NKTxsABTIAIVm1CFAzxRe0Ef+ve0Z4AlEqEJXDuCFaCA
tO2JX3xQNuL4uq597wtR+13f3rAEzb72t8/97nv/++APv/jHT/7ym//8XAgCADs=
"]

# vgl. auch Quelle: http://www.clipart-kiste.de/archiv/Tiere/Affen/affe_08.gif

set ::gorilla::images(splash) [image create photo -data "
R0lGODlhwgDDAPcAAAQDBIODfFdCFFRSVDkjDHteRMfDvCwqLFJDNIRqVGcpFBwSBOTi1HhMNKSi
lEw2FGxSNJRgPDQTBG9tdDAkHNPSzGNeVERERJOSjLKytI1rVEM3LPTy5C8EBFo6FBsaHH9iVHxG
JLBsND0lHIdqRF9FNIR2ZCkaBFk6HBIKBMPIzKyurFA5LNrZ3FlCJHlgTHJrZJyanIuKjEQsDIRW
NDUaFOzq7GNiZGFNRFlSRPX19GVLNBUUFJRiRHZ3dL27tHQ2HMzKvKWkpNva1BEOFJCLhDQrHFBL
RJ9qREIrHFs+HIFvZHZYRGdaVEExLEw6HDQaBCEMBGZDJGtaS4B+hEYkDHJmW6CalIxyXINmVEw+
PPz79Ozr5D08PFQ+LIliTIR+dIxmRCoTBNzTzC0NBGpURBYFBI2EfFJKPEUzJCckJHNgVJ2UjFw+
FBoaFM3OzHNybGNMPJRmSrWqpLNqRD8tJGRCFIpgPFQtHIxuZCAeHIdRLFY5JLi2rFdDLJ2enLq+
xFZXVGQyDJRYNOXd3E8cFC4uLIxyZHRSROXl5FAeDLSqnKxmPLi2tIRKJI+OjGdmZFxaZEQ+NNze
3e7u7ayqq5xyTKthOEwWDE1GRWY5ESUaHYxiVLawq6hiRIR5dNTMxKRyVEEMBHRSPDYeFWxKLLRy
TFQyHnxmTIxmVKlmRIxWLM3KzCgWFCkcFDYjFMXExFBEPINrXBsTDKWjnEgzHI1tXDw4NPPz7Dwm
JFxFPAwLDE46NG1sbKSapEMsFHpYPFxOTPb2/Ly8vKamrE5MTHZaTGRaXDwyNDUbDFQwFHRydHw+
HIxmTJVqTFg+JFE+NH9+fM7O1JyepLe2vIdKLIyOlGdmbAQFDISEhFpCHObj3HROPGtUPDUVDNTV
1F5eXDxGTJSVlHRCLK9rPItqTH93bCobDFhTTJRiTHx6fMvKxDMrJHxybEw7JB8ODGRELEcjFPz+
/CgUDNzW1C4ODGdUTI2GhG5hXJ2VlLRsTGZDHIphRFwuJFxaXDQyNCH5BAEAAPIALAAAAADCAMMA
Bwj/AOUJHEiwoMGDCBMqXMiwoUBhW3QIkyjMocWLGDNq3Mixo7yKDz+KJCiMUqJvsBoJiWFNRjYf
y3zIjCYDQwwhKwBVmEQJpMefQIMKHYpQR4tG2SAV62JIDQ8eu1IAmEqV6q5ds3joOfCvC7hof97Y
IEq2rFmhPilNejMNThc9VePKnUvXqiFw1hoNoaTjrN+/gElSgvUHzgW4dRMrTszDq4xGifoGnky5
o7BvRYqp2bW4s2e6uz7cgpSBUuXTqBMmMhDt3+fXsOt+ALeihcSEPlPr/qnjm7UBiGMnxmZGeOJd
XXwMs7El9+7nG0FWVAHnH2fj2DYZyuRvgrps1mJM//sTg6XLCf6K3fpwXW77xGoGCEkE0Tn0+wsr
6phUqdh1qZ3xoMYtA6gzjQo82ZefDjZIQ4wMkHRxgB4AfnZANm/05ZOC+N1X0SQx+FdhVSNONcsB
6KgjBCCRhRRUgxncE0kXPLymhjoqbDFShzwOJAwtF/BQYl3/TFDJNzZwSBYlLQwjQyY1dpbCAT60
8JGSPf4lnUCJCNFFZ9joUcw90mjUV0Ty3PaRZBh1ecMB73TmhjoV6JilbvoNE0iUJMbFQyYBLIel
jy5KlkgR3/TVE5cYgaSDNOL4s8liKfxjzTYTuXgnYMJM0osaAAxZFQ/gVNKCMIPiJtI3Hxyhgo+d
rP+AqkYV2aBCa4vxgE4GZ27KaSLiqCGqVV3cY2V0FU0kXTTYqEGNPJT8ccAw8ti5kUQ6CFHMB9jE
NeIuvXyTqq8cVTQMOHzOtYsW4tg2rkITZWDNNBnAksEBuwSTSCUfdDHJUDZkAE5w3k7VhTiLkkuU
Dn8YUle3/8RwalCotuDPB3qoocY7GItzixm94EJWIhn4021dPPQyxLsKMySMCv7VtcstCA+VbJr3
ZGzILlG4YsYsbohjLVl6fpCYIULocBvLLT800Qq3lFjhjfTs+JN+aW6BCxtupJGGK0mkkMY55nAg
8tBC2UDMBcXRxYM69DXXNEY6ZAMqaIEMo+ZQSsv/s80cJuQwzzleuONOEn6c80oAW6BpVgtUGE1X
CoF8c6Wmcx8kTAvoDEuEIcRoSJTcQ3QxSwrzEKA6Ci54oI07ftSSAjqwiE4USN/sWZcalVAid+a4
DVMMystYzjRG2wQySy0bPPPEM0q04boSLijhx9gbiDOWX5TE4BpdemCQyEhoA1+JIcOy0/tfuJgz
ixde+PGENg9E34YAbWjzhAt+bEABD5Co2l++MQDiJex499EBJR6RrlHd4FhlcdQZZpEGFvBBCRjM
3xME8IQ2RE8JznPBBhYQCC44yiyUyMcB2iaXAbRAbghMTbIokQ03gO8R9DGLT75BASO4o3oe8GD+
/7Shjfx5IHraACE8auEGWliNLBKBRThCRRUApaAYb4jhc4ThgwZS5R+V2JsOt2COd8COiG1I4/yU
UMQNtgEFR3TB/l6xATbpUCD08MdV+rSLf0xMi5URRiJ60aep7MIfVgKkRXTQCD24Y39PmJ8QMbjG
ST4giS5wRwpi0DgtycMGMYCL1NSwjkxhrkc2gMQs3MODZYxvMriAgSv44AJtCOCWaVQCCphByUmi
QJesM0IsTFg+s0zDYVb5YiOeeKdevAdAu6DC9gKzhW/c4hfQ2+AGBaBLYHrwgx7YxxH3cQp3UIAW
xdRhBr5XxVD9AxaE6lCyEgGJuHBmF3qYw2R0pP8jA1CgFijQhguG+E0+/BKD3QRhN5/BAlc0gQtp
CkxFWhAzubAjR5vCxTKEVCI1hE6RF2ncFjrhCnc844K/rCX0UPCMgyK0pSiIKf/qcIsxBFIe0hjA
KuVygVfdKRvvoQrvbAcYfnLNpMqYRxS8UYVTPMOkT8CgB37pvGe4wAXwQIE70mCEDKFGGoHollQ4
s8piJKlDEbEGHwGgBmpRRge4aBwuTOAKBCRhHqQYRy5aQQYyEOCqR8TgM54Ru1eIAQpJ8MIG5vED
zQHGBuAwZFzMekrUCKMSd4uLIWQlEpAiJC1n01oOjICAKKQBH6mQBScQkYZ5nOAXaGSdH5IRhVf/
1MGwYnjFPBxAmQ0J0mTugcM0n/MG9E2lQh+Yg2ctQgkYHGENRSAEB9hB3XnYQ7WcAEEqElCGX0QB
CsqIKR9eEQUvrAEVqChDHVIwi0c8h3PYKBEPavacRLCzKnqoBDMjyAVZbqC1ZQCFE+rwDjxkQQMv
SEczFlyOZuyAFFGIQl+94YUXNOMLzSjHC8yQAnFwCQYb2AACOpFOshBieO4RgmUfwoV6yuUDj7Dj
XxjmijjIIgtMIEUTtOCKd+wgARduBj8WzI9ypOIF3IAGC+LwAlRwYsEYTsAqxbEffLgCGrFIAg4I
sd/bveEfKfjPVAyhguVeRD/W8OIu1NETMzNk/xKZuMULbgwCHJzjHWaIwheAjAo5DDkMQ/7CF2QB
AhBkAQQaEHSQZcECM9yjAgNwxRRuPAU93CMwfdFBBjJrlUCMz80O6YQXAbAMMfpFaVdwRRmikARj
2EIW9jBDnm2BigULOQy2bgais/CFVKAiHRYW8hc0YA9SAMAM7MDHIUAgizLoQg/bKDFaBEINUFkR
ALuAhIy1NIkv2fMCicQ0JegRiA1YQAxmIEU3ZGGFeZjhF4lucDOcIWR+oOILtVZ0kKF8YVuU4B3v
sEceQGAMJ9QgFq1YZtZ06KhHBDUFRBACqBeiA3XMxRDPKqo8CHGPYBjiHLHIQhL4EA9SMCEPdf8w
ww7i/WdcBzkVGNYAP74w5Jkb+cJrqMEIUFuCepDBG8ZgRyw6sQ0dSJs3tbpBwQxhOU8K4wpeVIPC
b0cQBRoABnogBZbngQNZoMIWCfBGGnAQBV1kIddCnvcXGvyCRF+4B4IOg6D7/IUsIOIdxtAFGfjg
hSTIIhYp4ME50MEGAyTi6D+ZRAFb+Mq/vOEWBcvGtj3ik8ZR4geQqMMIdLEGWawhCmXQQBZ4XYJ5
eKMOWeAEKv48b3vjOwsvKAEw0h4GuDcD5hjOwhJY3Ypn9DoLskCAK+yRAydQgAI4YAM9rDWroPQF
Fpyeyny3ZBZCyiUTwxWK0hoHiiZQYARxWEP/3RPwAjL4IQuo0MCRvTEPYxDa5c2QA6BTUY4D42Ee
JdDA27+g4NtnGPZRMA/z8AKCpgEggACtIAuy8AIvUAYsQAFOUATbEEESIQ5BBQBM5xfCIAQX+A9l
MnECwQVzcAStkARlcGBBJmhp8ArohW9f4AXe8AJnh2H8gGtDVg519wLz8A5xAAIY9gU9wA8WhgoJ
wASy4AWhUgJn1wwagAojMAIJsGcagIOx5wp60A7LURaUAAkXCA5jMXmWIQ/fcAFyMV9LMxSU0Aje
Vwdl0HkJUAByIAc90APlwA1iwA36N3pfMA8sQGs0V2+4dm8awASz0H628IPx1wyjlwBYIDhm/2AE
6NcMBaABO4B/CYAKzsAPJDBkCFYCA9ILpUExICENWkBFVMEDKgaCOuBwLZR9HiEZsNAEesCGVpAA
UThz/NADgCZkI/AL+LZrLBAFJZAKGqABckBkCDZ6aWAGuxALTWAMX1AAr4cKL7ADXnA6URAHtFZr
L5AEyZAAS3gH/CB/+JYAVnAE7KAGTfADYHgtf3CBxQBBaAELBDMVatB4ISUQ5WMDP9AErVAH9nCJ
+4ZhcldvGtAAYsACqXBozZZnr+AELGAPuoAD9mAPOBALenALhvABm3EVsgYAs5AxbpAC52AGtaAB
BaBhtgAN89ANC7Z6FxZoF7ZntqBe88ALV/9ACETVZfnhA+6hDu3IEYFQho8ASMwHLQZgBcd3gkv4
BQWZb/uGCuXAB/VgY8A3ArXlbhSADOyQC0bAA7NgCJAAC4HQCysgDvdQBGWEDmcgDn2ABoSTDK9Q
DvdmC0wwDxuAYbaml6jgcuUwcxrAXRvgClogA/TgHEGZENLADhb1BkShAheYCf9SLgLRF/QAA+yA
fIc2evzmlHoZiPwgc1lQCDXwAgM3OF5wC1FwD6DQmqBQBJlgANuAC5kQDSIzEZRwBmMQV7TQNX5g
BANoCy/ABDWQBHVHgwtWkD9YZE24Z54HDa5wC0XQIokJLzJwgb0wFIlwBEHlLEDBAaBgDnr/QAE2
ZguiJ2h62Qy11pmdCQIjIAGaZwaEgwCZiQEGYABzUASBcAS3oAe7gA08sAmZ0AtUMA0rIASQ8AGv
EAfPkAZRgAAvEAfeMALaZWtQiXbNAGi5R34KCJ1OMAem0RGJsHij4lZAIQSSUxW9UJ0UlwhgsIJx
AHzoh2GpMHPpeWGBiIwXlgpMwAIjQAbvBj+S8AqzMAtEOguu8Aq5wA7/pXmuQAGuUKRAYwTV81Rm
MDjzkARM0GtOGZWBdm8FuZeXuGdMkAYjEA0T6ByINxAZ0EApcAOuqBEj+mKOyRE6Agvo4AolYGio
4GsZRnNyB3/suXY/mAULmQVxEAWwk0mF/+MOteAOXrCCykBLKPAL8yCXeAA7P+QOIIQCfhAFFBAL
ZfACNaqhGJqctgZocjdzuZYFJVADxdB0tKIDJCpU8ESZ8kAMFyh5MRQR2wAGruAE6LWXMSmHKZh2
tQZ/gpYK2nVoGuAHZPBI0KMNrMMHYkAGEuAN3tABotABmFAI8YAJ9VAP8cACFvRLKOAF5+AES2AF
hpqLyOmZx9qluFavcuCU6dCna1AHrmANccNPF/EGKUoVgWAaN5MROnAEcvEPrIBAOoILjYAOuaAL
VtBgtdaXGSp/4zhk60msenmvzcAJvpYFaSAGgPVNKFAFZFAKwNADgxACQAAEg6AKoSAHDf+gDB2g
DCsFQs9gW1ZwY2/XAx1rofA3ZBlbc6pajlYADRRgAaCgj2s6EDpgfVXxAbVDKwIBCxdIBZlmERXR
OI8wArkgg35ar2mnaHopk0aboTPJpXqYBFAAWEGkBB6QDMoQCtXgCKbACJcgAiJADo6wB5ZwB2Qw
A21gB9/0DElwDnNWa0EIsi4IuagaqE4pfxn6g4lWk6RwC4sgMg4hHcMQfQCQnVqkA/6wsISAQLjw
A5nQCjZ2ZMiZdgt2jIj4knt5bzvaa5zAa1nwCq9QSR6EAt7QD85QCKIwCHRwCYxAB4MgCoWQDtxA
BngQUwrFB7UQBdxgqBcGsmyrnrnmgt7/y54LJnMoyYQsoAdWIKufW3Evpr4YAX1ykQ3xlB+f9AiG
UAcv4INfcK/1up4Yhrt7qZzdO5PpAHMLWQA18AtK4A5J1E12qwGF0AHMQAfJqwoK0AGFEAossHcu
8EsX1FJkUAIZxm8CLK+CarsXu2C+JnNhEAaTGAd6EAx6876iGw0xVDcjEnjy6BBvEAiuEAtrwJn8
MMRs63IdO4No53J6+YMwd3ZMIAa1AESC9QytUAUQ3AEKoAqXkLyY0AF4oAHJkAyQBD0nhQIS4Ac3
im+parspCMBLfGFnV4O1h2sJsAbs8A+dwKIDsQW1OhXgphHfcF9ToQ4YYQP3QAGvsAYJ/+Cn6cAP
6dAD7BloP4i7k3yjJCB3XyCyqZCoytDB+fNLfkAAZNAM/eCtquAJdFAN3VoC3BAFtUA9UXVEzpMM
aQCO+ieTiIiIQ9ux69mxBMmx6skHrvAInksSBtFJBrBTVhEDGsGBcdFWF5EIPnAO59eE/hsG6fCU
A9yxLnfCHBsGl8x/2bUDYmBSCOUBVoUHZNAADUAGheAJnqAPqlwITBAPUGBV1ZNLLHUOSYAF+Ga2
Gbqe3Yyj8VqQgWbQ+8aEX1ACrnAGZ7Uj27YFXDA8JzMV/hCnC9HHADAA+FgU1UIJ7aBqWRCFCeB2
TunI8ZqCJUzJYcDNLbysWQANJhtT4v8ky8+QpT2gCFl8CZ4wCIrADNF7CrWkBAIwPazjChKABflm
tLl8rBg6tGg3tDSHClmAA65gmzupOVcQVG5QpxbxBkGFig1REYlgAedwgr7mpwKdoYKKsRaaxMSK
Cpd8YZzACRqwuDBFt536DMrgDQWABICtCnSgCkjgDHggAdVDPx+kBPvjXVLZl/LHzeGbb/dKyfNq
2fbGhDNHjVPgCvhAH9LBId/gbVVByBchA3JxCx2dEIQgS2WQAIh2e/qXnL3c1Ih40E2dqqgAdyL7
Ark1WC6FQSylCFKwCnuwCsi9BxFAAwRQBXRbRLmkS7ETBT+Ggx6r0gSZrKga0N0rqGv/m2HcRQGB
sA48WZkWFxf/UMwMYQMoVhVwoCAHKw/01ApbCmWp0MZsDdDw59ZPjWsmLGgim6juQFWagFBAJAUe
oAmaIAiCoOCCwAwe4DrQnUQHdVWuPIX7+5lrfd22Pa8DaWuhqQFlkARaIEALQQ0fwEIAwAM+1RDD
UI/YMDHwkgiZQAEE6GfjeKNs/GvHisuWXbvazaWpkAQnIEcdHNy/JD1toAl2oOAKjgJvpEb4I1gL
7AIz0Aqrl2j+7eFQzcZPHdXJScRZMAV14ATLZ8y5oQNkGBfZWVkEsQVAFRe3EKIJoQOEcAxJYA8I
5mdx94MtHYhG7OXb3dID7OcXVsBZ/3AOBCA/SlDgCKVQGaRL0gNHSf7o3VThT0Dd+XajhH65Z4vQ
8orbn45hc8iJWbAGSRAM+UALQkAPvUIo4sBTO4wQNqDRps0hwmADIR3EiEbEtZtr/g3qHp7LYWpr
6ZDJd/cLckS9Bi4FkE7Gwo1BVyVQDSxY8+MCYoAHUfi/uJzQb/3t4QvuRIbNMzfSxjACr0ABuVAH
nzAEcZUb3xBUemCiCvEG9TjvqqIDRTAPiJC2MBfsXSqvpwro4b7jREbXnGAMfLAAVxU9B4Wu1MsH
JzVYhrPAgxVVJiVeGCRQLkAAr/CDOl7oPz7sJO/nIA92tnDqCDACPAADdeIjlIAO3v+SDanyB7IO
L41ACrpAd41ctn+edvfqZ4OK3aOOo+rZyPf6AiOQDNMePYH1DJg0WHww9YZT9c9jUi7wDF5Axtn0
BA8gBtJ47Jf9mYOu3d1t9oS+5d+be19gCyAQBxSgBZVQzMKQDa3IEEpXFWYwAUE5DLFQB8PGD86Q
e/fNtkN27PL6v4EO5qeql+nACS/ACSOw6HL0BClVPafwC4oABaYXBQD3Dp4f+qD/DmIwD1BAADNQ
C/vjArUA9kA+wCU87CPf4YKGixeGkk040lawAWrwCHTeSM/svgUxEfXIA3m8I1swBJ3wohKABy/w
l4mfnPSarLXv4aLe1JkNZSBwYSD/8AoEED+sbwREGgV5lgIB6A1QkAxV8Au/8AC/oAzsPwOqkwwn
cA5RIAYRlljXuwMZS9DHussA0UzgQIIDURVsdrBZGIFhvjTj1+zLxHIvZHWbRUWHPHmTuqQAEDJk
JY4lTXJ8s0tkyAPShMl7uYUSLUmv2PGBcFCOwi9yvjgU+FAowoEMExJkiMrowKFZJo5I9syPuwUp
zrl5ZaSWOxbunvF59syFWLFjzbpwoc1FrSdizm1wJ8ZPs3QRDS4cGPHnQ71A+/KV6BCVXomFBSpE
VS5itymG3GQQtgUXpJUh1Z3EHKMygAs6XsKkhEEPAguoEihGpcHu0IcKCQpFtTd2/2HWtAuHOSj0
C6oRv6amWbDVxVSvSowfV4JCyTPlfJI7f6LEhRI/8aLU8jOLT7l0tmsfLehaPNGGh4PSVswPVZVW
ry6ogLnlyi6VIrtgNqnjxuZs8ihx5OKTVtDA4oUE+PlCg3JcA+ongf5SqryCjMINIaVY+yKV2KBy
Z60UnvAjrbS00ca4NrRpQwm1VBRxRRWXC8uVc7xw5RcNbitPoQa9C6w2H2kDisKgymmmBFcW2Yij
LdbRozIeJsGPo0S62AyQjYRJxBxX4pAli3K+ILKZL8976DyEfkTTrzODyoICAvzw45xz0NLmiTpR
TNGDNjwwzk4lovuTxBJTPMWPX/8WcOeVcxI4DE0JK1yqqIYOEtI1Mg2DSINf7EnEM1x0oOSWynZp
hKPPTJKGHScTeckGH1yxJ4sbC1AsIbt0xBS2MpvZCa8IwcPLvLyC+sKpL6AK8R0CXADUOD6VaCPa
aKE1kdoUVdTGA2ZQOCWKX14RIwsQdn1Up918jE0wdNEVFjF+ynClD1O30MGfzayJUh4hPqisi1ab
mIWXU5hIhR9+enjIqL2OOiiiXxk61yfbCDvXNte+sCsL3pLxo5YoZhjLOOVETi65aU+2VtrkUODj
FHd+ieKFVFKhbbahLCUv50cbAkyiMvnJYoNbEpFnC440q8yfJE/S4ZH6RIJEBxv/1AEgiihYKECD
L3qgmFdL7eLRV/IiFbKn3XgVCoQR3nwgigemc+4ZJfhAQW7njksxb2v3rlsqmF9wilKE1Fz4rx4h
OvzH14bVYA1XfPiPox82K4ZozChZ5l5hJhkAnU1IkUUDOQweffGzmQrPO8J5HCohiAvTcIRXDBXj
2uTkxn2541BoQzk+f4d2WhSAgDGJKLLI4tKFibIUZ2CDRezSRvmRI5UEcLgFlpJa4Helf97AL5EB
Ri1Vhy0+eeWFZlKZiC6J0hHMKBIOirBwpIS9K1jwVkNbw2PPEQsKSoSc4/iJgAckYO9KhoJXSCAB
7DOIUWzGuolNUFeJc12jBNKD/zAUIAv4oEAGkhSqyughA/hpgahWogbtyYMQrogF8mLDiWZwIh2t
K9PFnoc4dEFIKJFiSk+QlwYx1GI6StCTcVCENzsBSjlPXGC1hjc3JUggDTNrmG0mtRDBcVF/kvrV
F1+nG/ZRrwAlaIIa/mA+edRrVELAzxvU0K8WcCQbr1gD8h4ise+A51d9PIqQiKIwiQxGIj5xiix2
EAWxeABFAhBAtCIJSSUIYIkIRCAKNPmAZ0TBDzciV7Ac9SP+KS6UAikY9Y7VCldkI3LC8MFmZICf
YfCgMsEg2hg2EIvQ+QxIgLGfYSBlQQrWBmcY4xX7XuCNZEyniSgaICalCS1NPP/rK0RkQgFoVrEf
kgdnFWqUHCT0he5Q70HpGkoPBBKHKMxiGZHTAdJWEjXMCGEzN6CEDtiARw0oRJzte170XPedSoFR
gsNank8mwolUsIAMtRDLNCWKHE3sww6c9MIO5hEPgEroKLsxnOFYkxTbIOyGHWXYQhxUhleAQxyU
2MJLMmDLlfgjciaRwWZ8oAMu4KMOh8gN4lA3SqL4aEc/7Nld9oKg1LwgGc18m8g0qUDlaKJkViXZ
E1NkVbQ8wx1m8ELBeAgkC5XVowvjiU/+uSPDIKwZsqAAGDpVElg0aSUXsJxJ4DCqWQ5hA2XQGF/4
WJQuChKYB02dN8kEsTAgaCL/X2AnRKdj1WlZVRNbVYJV+WRZzHpgOhDlwzx+8QLdRHCoxeThbJCi
m8fuiqQQ+QkqZBELLRDCJKwwRGX+kdeSRMJJf5BHEChQBtOoVIJEbc1r0TlW2XRtKEv5iV2Ymook
PBQsK4OiJke23QVq8nZS8cI55gEMjTFXi0mhEIMG1zq8OIiLP1LnWxszDB0k6RsqFIke6niS8a2E
ByuQxxxewQRZRMQhDjklQXQIyMMAMUdlU20YGKKX2DAhHmQgAN1yFxYYUXHDxsGdC9wBD3dE4Rwl
eOCXGEK2oBq1NoRBDHvNNB6I7AQEFlDDI0wyiQs4ab8mwW9IPlCqaFAgASXg/4PBEAfKwqincF2U
kHMpGLYH4QUoCdFAFrzgDQn8gg9eeIYXwAJmPrijFkmIRxLK/GUvgDnMfDAeKZiQgPKO9LnOU3D+
ghIkDZpHNkPhRxhSwQQKsCMQNjCaPGzQX5HsooUmye0KtWeBDegiCmmYiBycIbEM5uxHuHqwn+9i
FLAdOCGPTUUWmFCHeczjFWdOwiuS0WoyRKHVYoiCGLxxjmS8QnYjmEcU8CCr5BEWf3Y25LlW517U
OYNWqi1ImbaGihfMYxfoyCslAjGqYWBmjisE3w12MYsU7ACkGONfzWozTOXxyC6MZW9sdvWTBWUo
1RqIQxJw/Y5cv6IOJcBBN//yOIUSQCPWshaDGJLxix2AABWo8B8Pd7QUB+csKTJGhTMUxI8FHa5h
QDHGO1IACRuURD+bOaFJhGFXkRzgG/Kgwj/+8ApdnAZj5NqNICM1UtPiuZCpkzYEJYQKTnzhBRqw
hQayuZss0BkVGiNtAhKAhaTL8AtJTxCOyENUirU4yg1DxTOYUA7EtlUghIZENG6qg15sBo4qp2nL
hyCPYVBjEq4oQ4H/WbrTFsaQRT2qxHH+y/OAwDDnZqi8D9JPgYRJqUxFpWqSWrEmq1dHglNvbM9z
sXI8IxnAoB+naaNkHOgBFPSIDEd0kLnK0IJpcWdJHYUhDFwcIBZlKEHDOD3/+IKkw+uDw9+FfAXE
DDG0TI0VVmMn/CBktibQDVmxkhXT2OfrWaXEfDGmbiNtgWiAACMoB63OBhRcJcAPTqDEqdoYy8pM
g2ndEwk7fiyPXrjiHe4QE/f3HGglRyTQ3TEP/2s39vqOhTE8paCe6IMIrgkDrlEMrUmMxBATiFA+
frgD/jOYBkS+ZtCYwZoQneGJovgCZ2iNVGOCeZgzmuEHAMwNvniBNdADHTsJYWC9lXg7k4M9ADiA
Okq0H3CDd2CBoNiJbQqM0QGLG+kBDnIYpOC7h3kNSwGng8gCmjkkCTOYMDEYMOm+F3gBYygDJiiD
MOTC1BATCcMYORgdJUsK/w0piK4JKbISPgnLlAxJA1cAgSzgBJ+4IabQmi9IgDigAPiYQXNwu9er
jB1UEiwpAknwAtegmaAyCmVIhgJQijAQp7swsDRJGAzqup6gQH7QuAKgRA3AAnGJgw1IAgpIxQ1g
B1eQhCSARVgsA6nTAK0hLVDkO6YwpMvLn+ghJLwwGGfgB1usAWiQlRfYw1sxm2bQABbIBC7AjwnY
DOBSOfhjCXo4CRuIhRIgEugyrrOLAi9glEBrjfsBm3Yxkx2Kth7YRQORBSs4gg1wAkkIBDAIhGV4
gxZIBCqIhhb4BliABHA4A+xxglvgElsAAa0pALqQMeTiEZ7wC605MjIAnP/kSYV0OCliSZAXqINP
WBqTa7vKuMGSYDmWeLmi4QgGgIY4YLLY4DT6SQDZsYItCsD2Ipwru5RbEQj4gZ+geLgseAEE2IBA
KAZ0UIFvSIRpiIZv+IZJmAZi+AZ/pIIYSIQK+IYjCIZgcAJoWANOsAUiRBic1B/cECedOy05CANn
q7cRSAIZSgWFEieeiIgCqIN2uCmTu4bNIImT+DaRUAPwSTQXMsgbMYwQ5MAsWCRdAI/nUinrE8Ew
arLAgJ8yobMsQAAKmAIhWAdquABpYEppUIEW8ExpEE2mPMrQZIVi6IQK8IUmGAEWWAOtoYskzCGf
dEiccwjF8EMmIIMd0CP/CEpGiehDDfCCWOAtjqCE/aiMlAOyEgKEk1gHdjCGoFqspkoAK6AAUkiA
YgGT+jEvdqm8aFMlbcqCNUAAJ7CAWKiEIWBKWGDKqJQGaZiEFniDb/DM92RKVmAF+2wBIQiGJnAC
XUhIbXo+ZAoTiqOxxZygiKhFAkgC9UkIGkKpDEEmlqoAmMBQ/9i2ldgFA8AMKlkJPSiVwBwGdoBQ
/BkIL7lDL4iCWWyG7dQ69Noib4y2K9uJBJGFMnCCJpiDb7iCbBiCNxgCf8RP9oQFdagEcfCB/WRK
epCGN6AHeviGaPiDb5iDJvirAmsfx6MgwwEKKiwTDcgajYqDjvMl7kMF/04rAFeYA8xIhGJwElbA
DEYLCR4gicBsBAp4AerUomEslhNMggSAOAP7TgqCt587NZ+RBWgghVt4g/psAav8hgqgVGlgT6sM
0kBgg15ogkqIUimNUv48yiEYgnVwghOThdMYiAIgF8iMtvOQ0MNAhTp4BcNsBsPbxPUxG94wh6V5
CR5zkpM0iZAUCR4Qh5OYAwooLz3zvwpBhVN4B8B5uMCYlIrLoNosjzAFAVlgARzohF7ohRYozfsk
1fek1G8YAlrIgBjwAfy8z6isgCGQBqv0AQvohCPwgjwyUC1ylI9in2TUgB0Qg1n8o1iFnfYZRi+4
Bcy4r0OEkpPIhspIAf8ZCEx5uAIjsxQIytXDAIZ6YAGg1JrlY41kYysteg0QAIE0aAID8McM8McV
IIb6HE0iJdJvqM9vkNKoxM+dFc0ViFcDCAQveIG907zClFHhkwj2KbpTizWpU4rJrCFh0lUG7YZN
mDuTUIED6JfjlAdr2Ax1WBodKAJ2gNFeObXSQT4GfQVSGBeVQktw0h+cgTa98L2HkAUnmIdHoId8
tE9A6IUJsAZxrdmdRdf7LE38jNRJZUoiHYIrcIU0OLqFNNkp08j1YcZRkIAdEFQKbB8JXZgy2okX
2IROOIlhKEkAKIaSO4lK2AybMrlPSIJt6o5doZSEUYgyIIMSCKxEXRj/NJk3n+gBrWEfK+CFY6CF
YpgDf5SGbBiAC1iGP2AF+hxc+/xMwnVX6R2GbBCCfOyEC4gBLJ3CgxEIPfLEL9K+iUAeWXiFB523
CilH3r1E6jKHDBWGFXiakMAnzICFHCyGbSgJSoCBOvi4eaMgEEgCb5AZ9QKPSjEKjS0d9cgCW4CG
TMhHFdhPSyWGbFCHUXVS693Z+3xXnG1PSABXDBgGWBiGFmCFTIAGDbgDhOGEKWwGdbKzYBHfVMgy
RKgHzUWqiaFWlbqhZjwCaDQVDPjaj+SIb+jLkPgHYbUBfHCCceyO2UivSxSIPySDOAgcwuOmsPmJ
HlCoLCiDOuiEqLxZ/539hmH4zBCm3jb24Oplyj9QB0i4gUqIyiGYhDxVnxvRoxsquxaTgy8pliyo
g2TAYcLwqNdAsKTVUVAwuRoUiUdQP47wiBJ6tERABy94kB2xoCtDBRAghUnEIvNVrCySg4XMAlkY
AS04AiEoXMW1WSml2Tf24HfNWfqMgRUgUmkQgnBAgFcIOolwq8ADj1NmKHYqgyzriTHyjl9xqy8A
AQqYg8/QAToFADvFDxuwFw4FMI7YhliIobFSrEIiTjJgAYg7D8IQqVxxCDmQOmiwhyCoBE+9zw4m
TUml5XxuY9KkB3F9z/6khXWwh09C5y8GwEfhi/bRgBcYAVKwhfZpH/9wghTTqZ4sGIEzSBIbiDS/
NIBJ9g9IDgmK5YgUYskZph55EzxMSYUXiIJkYIKn86Oy8kYHobYsSII52FumfANCiE+c7WDCZWM4
tl4V7mcoJc18lNlJ+IZO0FM2nE3IK6RQ0pAsGIV5MDcIAhs0iZBnDpomyKeOyEEnkIYoiYH7BYAB
SDR62AAcyKJTArVz0YBTMINho7OE0ZXByiE5vGIWuIVO4Fugzlla9ucWGFJ9duN/ftJ1uAVxRDe0
5JlXnYjUOBY8SGCC2jqfSYejw4E6YACOyADKST/8yIDTNYQkqYA6AKwZRlN2SRBUqOoW3U4mS6+4
fZ2ksIJawAd/EIf/w7Ze0rRZpmRPm22EFVgBaoDUfBxNoX5PNhYHf6C0NTgwJTu+O3vRYuGGeRiF
mRmWxhwp32sIiUmFKXCFH7CjzbiGfPkGrV2JFOBBWKAAC/hu7hMkldKLBEiDDmhL6lwXqV28OMAB
WICFo/RHFVDq5W7Sf35PIYAEQ1ADPVADNbiAaICFRPjrwZWGwH7P+jQAagCEI9Bi/0vTGRsj5FGb
QthdoXrfX7mYx5ID5KGAIiiaDRWJFMCXKKGEHquMvWwEV1gDFXQY7rsgXskap0iDKNDdibBWBF2I
nUAFBACD4F4BIVBjVghq+eRbaViBC6iPXSAC+qjTG3DPD3bXIl2H/6b8BjDwAtUYk9n4vaCwhTgg
gzKwXJMNvF1tiBuSrQ1Agy2YBPVuNFbwaFNhv5XwAaMRAgpYg4OgYdRR4OjyCVl4AVIYMA3ooMMh
Zjk8iARIgk8Yhvi8BnD9YAz/BhUYgkc4AC7/B3QAB0iAhEDoAjcAgF0IhEaYhL+mZUqVV1gIgDSo
n2LTPr9baVplnxYMg548PjBiihty5ywAREr4AWsEADVQ3RnkCHvqF/PJB0SnQgT5YWJ+vhcAgQTg
TXdwCmE5ncWJEFSwglc4giNoBBVYBkiIAScV9QxPBHFQg134h2UQB3GIgT+IgX6nAi3fhQEYhlof
c8KN129YgXDoAv9S4Il+YjY2l4gEsId64AahY+YQ5KZeYY0cpQADwACzLoZ8gYltMGsWEoZPyIU9
RZzjkhSewclUY4EOKIEuyQ3H2w1OgDjB4QdxPwKrbIEYQIdiiAFJvfB9ZsphUAMegAQMAPgYCPiA
/4Oq94EmgYTpRdzo/QEMwAAqCPMj6AZb0KYqO5urE6u3ooA6MIaL7EmJsKHD+SIdAuOJeIUAAAf+
MHmYcILKIIJjXYIRKPc+4iab4SP/eQVvmMXW+JLq48CIa6w/bAJMfYNGEAJA0GcfIALdngaq/wN/
7/d/F4Je0AMi+IGafdejbgEVUIdAyAbfRgffPB29ZsaDoMJYSAH/JwCBtww0EqCLpVUqOAwKcyqH
OpAEVeHQbtv7vKyMXqAEe9gAX5fojV0KBJEgTkgARBADtt3OMNBN20g13ECYckADGGBP9lRq5ZXS
pMdPFfiHLuj3+Ad40Kd6qQcHIuhHwqVP/AwAH7iBDACISYnwxUnQrNkXVAe/IETFEJWGF64uuDKW
Kh2/MKjCfOGUDmEzfgebhWmmcKTCLz1EpopjJgWAmDHZtZBn8yZOmxlkyvxHL5aXLAkZimS4ECRD
o0ibpfqigRuZEU5RbeRY0uTRMGGyxHGVqVeFCtK+kS1bdmyLb0LUPIoR488ft+Lezq0rRJyhLirM
ji2b9tsKHzG+/0U6YqREswIjsZYU2SzLmhE5hmjh1fTL1Y5GTyYFWdLhQYxyUK0xwzPmNUryhOXM
2cLQaSKVoAVdjNKoxoNX+X2RcxBVqqZZWJDx86XcwYwfP5rE3ON4HHSNGrWoYPa63wqPusj9I24u
3LduY3yPAekfLOzqh7SQ1qjPEW4Jjn/JkiV5mB4mZcVht0JHERS8YItvGvXWGWZYLYaKHPdhxhBk
s5y2yx+s2WRhazb4cxoAkNSBg1Ag8eNQZkvh1pkcLzyWBR7edIPVgxwZRRQ/LeEzBD3f0JOjNDyS
RU9fFbQQjT93kUcXed955xZc2RgyzF/X9fXNEGOxVwE+iDVn3/99+XGUgBUU9KKDPKA4oYsGJx1F
0mJFIfSZURg1k0AOMPHEDiCt6SlPDDycNss8BTG2WIK6KfiFUjAelMorrpRRjkEkiaRfUvqhYswR
BrBinXpTfiNNC71MsKQ43pkqV5J/WHMFemepR5Z10qhQQSwvFOAMosD1xg8/zhSQwAZaJGLTFj4Y
kcULqYw0FEhqMmgoU4giKgs7dso0gGp75vTGARzuUoYsCIK0rIlsouJYQ3KA8AIpr4CgZjocgRRv
OqiAkAs+4AyTYwtvRPkjWe35AAmpR5K3pHel/iHDBXu9WlZYQ2RwAz5JvJCFHEnZ8oVi6XxhSxx6
dLLaahW8kkP/AsCNC21SGZ+7kJrInsPhI9q2RkkxHM5jTBYKlZQbRySedNXKC8mLiizQAFBCFgkg
13KlB61Rxz2V0DPGG4ScleOnZmUTyZLjlXrwXOLFkM0AD5tl3RBvCAEHBVmUk+AX6WT8xQuXzgOG
DhjKE0ga4SZVTkpvonRVbpcxVYJpPPHwhs2tCaFzGZGKa1tnIhWuFKLNhIlDDfCA0BxSDD3XTNL3
VCfNG2p/428nXcRlal2oHlnqANH8+2oFbX/TQhFeaMCmHOkU4PEXsoDgCgyJbIHTFga8gkMqnPz2
2bLy4kY6oi8kwWExfkcujw0fnGZGGj1DmxxSV3GG+enNZHJL/xCfkFLGfcs21YN+qGdiAT1YAYoW
sAIW60jLWHoEMGkUwwdxqd1crmCwucigC8OYhJTIMqXexcoCBWEQQ+TAD4zYIjLFGII8yIQTLlgg
DdXzTeHQpaaQXKUpB+HGPDgUg/G1Bhwc0oOKEJKxZrGJXJxDyHO+MEJU5KIdOkhEE0iRLIQgL2On
A8EakNGLYjziGzHwQS9YwTW+pEUItyjbeCQoNjX6AxL/8tTaKpCNQATgFvaI1KR6kCJbbIAC33he
a7bgAFIYgxMMCQNyftO+h5QkIQhJBQsaFxNsfOAbPMxJBj4gSQCYIRbzCUONZtQQRh6lPl9oSjqe
0xKasIYQA//IRRM4oQH+PYhSSLtFLPb1DXVAIhuw4NR13kCPFiyjGKsqD13QKI5eoAMW/lobWYYQ
lnWUZR1zSMMGEqCsU2JEPyAI2ci01YIjIKBpiRlioWyjFTalAgRZeMckZeIDG1wSJ4nImUywAQBS
ZIEfPUhHOmyozs7U0JCpRN4IJpAtYUhDC06wBRNSQUutYGY+9mABLAgRwF5kIxsGgFXXfkcWWECi
GDIw0u3EQQtx3KAYGXiYNNcRDTgYQBqTCEsa8BeaziVkeZ/IlrbY4AorcEwORBuXm9Y0J8aZRp8A
0EMl6okTHcgAnvEEwIsOZL2QvClRXG0GCFCZKxy4AhQ3YU3/I0ihhcs8KCOISoAs6vAJesCCGkIQ
wjdmJaUKPJMV6uiCP8AzjT8IIQa96MIAqKNB7IzFGiX9AyyGMIlPJMEg0mqGxyLyIUKMjxB1gEak
FFMo0JykV5pzJynyCQBsdGFYUr3JN27BIakg5LIz7CoNl5UUWVAABmSykDCEMYdc6EJwiOKfY7IA
gjo04QJ4/V0Ldve7BNJjEsNYhhaK4Q9w+KMYXbgBMao7FlaA1CwZgAQ4YiCNaMQCDmnI20j+WR8Q
QCMXFbhQ5IpACrwtyHDsC+Eps8C4q+5ih+K7pDDUwaEoxIGtCAKNgjKioJCgogxGaASGLESJe9QA
B3kYXS0R/5WKpOWiE2n5ywbJIsytfQMWC8uGNf7w0sWWZYyfas80ZJCBSQzhCq+IhSwUMkIhygIH
FPhDPUGRBDR1bmWJwkhTNACCV/BEnwdw7Wtv8oZdcCh9TV7MbjxD0YP8KgFGsAAX9mQDSLiiCQ5S
yQh9c8o6+GCYAQNVjVv3Oz37hWvsUQ89+BwwFUS3BfTYhhU28ALkZASU6jLGJpZBTz0B8iZboAQ+
RiAL9S3LZ0nxVYr40wEOUQG/WbbJBBYcB1m84CMv68xIQOk+OZSDH0zQQyP2FFxKBCIXFrDFCxAV
L3RmIQkB6MQAMnDiN0jTL4I2CwJtnMDXjQFIN7apeYZxhv8RrGt4vWJIKoxBCn9QAqg87MMImCCU
EaHrIcn5iDv1wCFDWJJkp5YHINTAIQqEa4i2AQ1RiKaRcqQhB5Q4sE3IxIoB1MEYstCABnj1oMdM
oQ63KMKdCTjGE/OFsSo2y470jOdAL4MXdXhBmhIDM+/xgrOv3QbDN505o83oYwiwVkzeQQVz35sS
N+CQGagnSnkhbiOj9A0/kmCFSmurAkfQwxQSoCJZj4Q/dSgCjlqQHoANIxvUjG5Iof261yVCBTxm
BY6my4p+EaIIrygDREJSa1RkQRYscAKGER65QV5sJLy5bWIgM7N47uIA67h3a1Sg75jYKRkvGGLQ
SrmUVGT/jB8a8MMGVKit51ECBj+2hc/YRDgsFIAC7TBAL9PSOkLcABKRuIE4yKue1k1CBbCQAQZa
1wJqgkoaN8gHLA6Ri2BHnKvHAYEu1PADzdeTNTaIhRPyNyIlIuVckIrkaVJwDx0wH/E66AXjZWKG
Z8TPNuYXCqJ8Mwo/bh4n2zjDKzZAlWaQ4Gf8KEcq1rCBDRRDz0N4nQyoQzQEQxd9io2d2DD4wDJA
wg00wjdwyolRQxfEwga8C2bdAa80QzmAQBm4QRFwnzCQSfeNDxtQABOABroYCiJ1gxtUGTYcgMsh
Xk58g4TwRAqcAxPo1mU5Ukc0g/WEgQhJRDjZzBawBiXk/wMFpMH8KcRGjIh9xIIh5IOOEIM49EUG
EIMY0dj/PaDWtd4j+AAgwAoGUAc95IMTsMAaaACieAmtJUAZzELzaN4WzGE9bcEQOAEC8BRumQQq
JEAavMRV3YPenRprZAOX8YQZsINQqKEtWE/+rNMj1Y3HoMII5MNrwYIWUEATCE7QjAikvMAvZAIb
dEEliJQKEII09MiO/Ih19I7WdcI3TMI6sIc0zFEM4EAuMMHGOEQEOMNKUEUZnIM5cAHTycPzFKO2
hOAjnINQOIQSYUQ5aMQSHMEh8kRryWBOWEgLyNb5xAFTNEVw1ItWgJIiPcgXjIA1SFVwfQM4UACI
yIluKP9RfSCAE7BDPvhLI4CDKopFj9gU27xBWNwUSc3iOhQBO5zJgDQFP8iBBgCDHBQAFuTAOZgA
FwwiD1mICmyAH2xM8YiQSJRDOUwBO3DIB1QINmZjCvUJh5xDsnwBCEiLnP3GKS3FCNwDggHXEATD
PJRAAWxTMxhVBtoHDjjBLZwBPqhDIvSINciAWBDCH1DD78CCD2TAEBDCEKBDEQQANBScur2kxIGS
S0KUK1gACo3gqXFBMCRBmjyk3SQGpGxANcpEIEzaSWbIhpxPGliBgzRD+SWKSszZMlwkfgkXKbTC
PJwCEySFP3lkQ9gCCGyAHtzCErBBJ7RDNAQQPYBDPlz/TQVAwhnMARu0wy24Qi0sGsohhEh4ZCrY
QhbYwwJIwuEVIeIB1xs4ATcoCyfwBkP24Q7gXEzoASvUpZ6wxhssng160n2sRMakAmc0hbxoQBrA
gEW2hg7MgRo0HCLUACZwQ0su5gghDwjIQpF5wf5RAAJYAAx8wi0EwyfcQBPcHS+kAS/gT884w5oQ
RTPYgjHoAinMgysEwwrYQN+cJAa8goqkRK5I3eDxxC5kg70JJ06wRjRwCAC4Acp5iUhwQogoyEdo
gBMcA8/tyfNUZy5QwBqwmvfMAx5YhMcA1EKCWwFARH28wAsgAg7EQQlAgy6UQByUAQ68gDFoQBYE
R61R/1+TQUQWcEMyzEMdWAAO8IArJNZJJkImsADdNZl9+OEmxcQtTIKpQShO2MAA+CYAGOi5rIRw
wJpK4J8uFANdRs4WYMAs1MGJ1kdw4MAI1AMvhNUpIcrxmFZR/J0G3gcqWI+yzEtbcUYfIgs3vMJh
MoEGwFUCGFkUoEMnTBprTOdUDUNFIAiyyAICbCkAqAEsgKnNDINxOlUKpEHKlEPECRRYJUdw6EIm
YNlZUeccvILFJIB9JETd4QMvuAIpsECwBQcngACv3EEPaMVKgGX8VB5f8so/fSPdJUACGMMO1ME8
jAA3FADhiBgnvEAJkEINQMI2nNoW/IEevEtShNshxP9BDp0GNmSDWZpqwt2DU8WEaSzADpDefBSO
bslBAmSCFsQgSt4EKNxCMjSNUQSHfYTnGuBBFLQCHxhDAtgCHhUArzSGl6zEP42Qbt6NBhyrkDJB
GiRDFLxCHLxLI9VWcDQFH8zDMWwDLkgVmdwDBYCAYihLFuinK1DoBdiqvaLkz3HIAqAMKtRaUajL
QfhGKuDALUiDzZDJEGyAK7yAZZXEaLwV3oQLC5ACGdSAF3CnU0DcuSgRb0hKD2jsceCfQ7ykMXAD
C6AsKTwDyq3hOoWB3bCtU5TBPDiBAegAMoqoPHxCLtwHrnwMCJCCqKpBcA6tzbBCF1DoK1gA4ZTD
sh7/ikhkQRkggwokozwkQiC4Ag5YKyj1j4ho4IhERAnwASmIwQikATR0gzG4UwJAnPmlSSooFxPo
AgvUgTeQwbACw4XeCih5GkDVTedwbg1sQOBKFQw4AbLyQwGo4SlI0iHygDiEKOSelQ4IgbxxiBG8
gFZIHFMcRSrYgxOUqojiQgDMQhwsmggt67IeUvk2gwaMhkEwASLwgqO+QyuQAh6wQAlwAxMwga28
ABNwQ+smgSu0ghiIQRKUgDEwBOGIhDNgYBFVHm9IS32UgSsgww9IVRPUAaE6BS9EgWqtFiS8afdG
aMLlA5fFpRkYgRX4DBJ0z6LQ6Ag0wuBSgg7IaQk4/4Uj6a2bdPCbnISazA0TwAMfvEINGOY7TPEU
A0or1EA88EEDVO+CxEiMmEQjMYdMjiwnkIIa0EK95sQW4IAkvGoClIAKb2kmCOgLgy6mUSj6DCk5
poIGMKeyrAEF+DDTWcgPqMF7zY1jOJL5lcjM0Zoz7C5kGIM92IOPlkEZGMMLgMDlsgmzKMjmEJHx
YZbH5B8F5AIspDGxbAEFEqouxCs2vLIZvCD7airkCsNPrDAApAALWBZvIDJTRMYQ5sQk3IIRTMF9
jAiutGxRaA+0NEYHO8SQ1p0sjJh4Zqm0yEsRlcuEVZ9uhVv+qRUKPSh18gKQPYUrNA6XYcMu6IEQ
pP+QONfxl+rAG8TCajmVaaSAogmp6fhTM6xBLkSVGieCBbQC/nxZ0SixoTALrKFEcNAd3THnfWhA
IhlREYXZxB3VjARHfRjDPMRCvWkLF1BADvBHvMrELmADDwjBgMIz6KYQql4V40HDC8hcD0SAfryA
GgD0VGHAOZQAODLaIQEcMytym3BOk3mVTI5EIj0LrAEefnKyIcmBb3BCN8zDXA7iNqhBE6DDz+aT
Ps3rQr0zSxOLChHDB3w1T7wDNPSqTUcA3vyz+PQBBdSBcTmGM5pfNk9cCqYt0ilFI8ljmwiRIn9y
UiB0UkRE5YkQV/CAOmiLDhCCHsTCz27SK1+Da9H/MksfXCXowSsDQDWagROk4RcoazO8ADsIgd8M
gSGML1F8RFLsBsAtxb/55TOmkj9NCknEiygxxlMjTjwWTfUg0UpIWRwwNiWMaE4YgJ+sVj2vFhFM
AD1hNkuzBvfFgPl0tj2f3E/yxr2g9k3gwifMAhMYhIuyTKwdTlfF9lD8jFGNY7zoh24v9MQRSvVt
TyinxLJurixsACk8Avfdqg6IQwrEcjy9ciRwlnSPtU1Qgg3IQFyKn4AwhJRRwA7dBCzUwQYAW8R5
zChRdFKpk/khjwc/B4kf1xFR9DZL3qGEhAjJmfLUgcgY403oQAwYZ5UVg9RmqoLzkAptQYCbD4XO
/wN9LtcVWAgX2EMNgMBLclUKNkR/wQx+vnZhm58HezAVBTZJCBluyZBsl9JxKIv3uEEj/FYiLMMM
W8su7MINGGyCj7UI4kI+nLNXx8ROZoEVjAAbAFIn1AA0cAIn2NBQo/gh4bVTKwvPMoX1bFXpwJBS
EfpCk8RmaPQzbiA7aMF9fUPR6ms+HUNNiPWOXxL35cNyw3QUbMAaJAEbpJAqbwKf6oZTY/kikYia
KhLdRbOQ8moqkLc8MkS9qPjEedVrj8s2yQEGZkET8EAvZIAWnPSEAMAAdHqbf3pO6EDsUOhv6gEG
CG4+CPk1c06hAkfhUAr24LVuZATSKc8kBwMOxP+CFtzCBrBDGhQA+Z5ObmxGY2BWw47O6CA0pI/j
jCwBNKgwh+jTLFBBmkk7NmbqMHQBTDx4TKiDDnABOsQNCiI1l9iQbh/FETu56YCSkGqrK7iCGrDD
LXTBEaDDTkachI3LJ+cHQ3ACcAwp5vBlfqDmnLjhCIiqPn2ADBwcwtdl36jA5Fr7B/gA+MbBIZRW
b9TWojCFUCN1ilvFQ3B0NDSCpuyIQGzDEVDAfEC6b4AZJ+vtooC7axtKRiwk/vFqHCwog2KDGvwB
Pf3Wz8+mO9tAL4w6hQ7VGjwi9bW4u6XuMge7lF/FaMRVLgzLgQkV3P22SLiJURTFbY1QI3GEHED/
tBWUQRKYRuPgXC4lXLTP/cHKAyXIgCY5fEykwRRM80LsM72MS6Lw+/bcO92tgSuoQ3ChJCiwAzRs
2psYFZtgj7i0dn402m/U3RpAQytYOwDMQiBUQBGq0OeD/q1eSCV0Cx4DwDx4Ad2JiEpIfdEgCDa3
bA8wYd05ASkcnpodgyucqINwRH5D+oQ1UsZ4JNHQnSyUAQWQqUlHwzYIrvRDLkAk8scDQEGDBs3M
KwEiS5ZUX8LI+fJFTrMvzTCiwhgGY8eLF8Pwc/ZFlhVom/IJUymPZUuWBrq0spdFowZ+HPl11PnR
osWc/Mq9aFgmiZmDR1NsaLTFZVOnT6FGlTqV/6pUYTbuHTCYoqBRox1exQGRgBOqVBX5XdzZ82LO
ZqhwBk2QJVYrGTam6gB1i0eZsS9G3gyTTuPbns0qYtQwcS6TDfOOFtwFIMWuG7DkMa26mXNnz1B1
ANKCLTJCM3Vw2GqoUa1bnYVZ6+SXJUGsd73wshT2VIc8HayCzQomi2azkMZ35vzCT87DF7ZsGWPh
ymhkbNh2fRDHhWnvz9/Bh2+6m9Kjf6UPmqGgi+GXxRgnsg3zkSPbhjjmTci9m7dueTbUcWUD4rLA
yK0vUGlruS9eAEEWEMpwIgr0DPrgGEK28E68DTn8ThhYwCFoMoNIMygKUqAp4KF0LIKoMJ0O0/8o
C27mOWYSefjjzynNyKNCjzpeSGAjiOBbsJlUNHghjlzesS69f6axYTcdeOzQyiulSkSIW64DoMSj
zEgIDyZQ0aBF+JpRDrHCbOnGlVgI2ZEqYSgRZxMKhFJLIySPPPIFP2qYEL0SefhEGh01xFLRRVu6
SoYDiKCwKwCSYaGMNWjTiJ+bIpDjuBdi4SGQFvzzbLdhnHBFl4ZASKWhLKx4AQEKqpMUgA9ukIbR
XXl96g0ftDJosi8RiuIVS4PUoJyQwkAlgRfS4EGdbcDbbaU3YGjFiTWI+6IMBJKYp1ZJifAng9x6
TXdXlXSABRKCbDXRlSRKKCABWxLAooxzeMD/QMoOhdnmD1JIiSMNUuZJYVwKd8mEmBvVjVhRRFlq
YRlDJhuRKzAPSiEKIySRhIdbhtHBO2sbxdEla3OUJ5FEWoClkntoBSBMW7vUY4CSJe6ZVx2lkUGL
EQeNrLoDbogmBmKGeaMFGyjRQUeVTaYkkW9gyUCIR3oZoIsPNk7PVjV6oYaSlFX2WW1FWxBiAGIP
gjtuL3dxQw01DLnlgmICAQccSMDxJ5ABLrjlH3bU+GAWop0sSG4ADMlGhUTXrrxXerK54INI4+3c
cwqJJY00Ig7oJQPKLU+dVx1sqESdcHjo8vPZJRXdy+tE/+eGGKSRWvXf1Z1yEkDUGXph2pG/hR13
bA64Rgh6zgZeenUpJ6SSZS5I/PjkbSVCDd3zkSZ61Kcvf1HNWmKdFWKyueaCA+Dl/qhd9OgiEHVi
GIYQHbsz3//KKTEJrAnhHtcYwC300KR4ZccQF7iBD2LQCFYQ4l//s+AFcaQDmEkDFsPwoAdhwYpv
TIISU8PgCVGYQhWukIX+CwgAOw==
"]

proc gorilla::CheckDefaultExtension {name extension} {
	set res [split $name .]
	if {[llength $res ] == 1} {
		set name [join "$res $extension" .]
	}
	return $name
}

proc gorilla::ViewLogin {} {
	ArrangeIdleTimeout

	# proc gorilla::GetRnFromSelectedNode
	if {[llength [set sel [$::gorilla::widgets(tree) selection]]] == 0} {
		return
	 }
	set node [lindex $sel 0]
	set data [$::gorilla::widgets(tree) item $node -values]
	set type [lindex $data 0]

	if {$type == "Group" || $type == "Root"} {
		return
	}

	set rn [lindex $data 1]
	# ... error management
	
	# return $rn

 gorilla::ViewEntry $rn
 
}

proc gorilla::ViewEntry {rn} {
	# proposed by Richard Ellis, 04.08.2010
	# ViewLogin: non modal and everything disabled
	# EditLogin: modal dialog with changes saved
	
	ArrangeIdleTimeout

	#
	# Set up dialog
	#

	# sequence generator - this relies on tcl 8.5's incr that will not
	# error on an undefined variable
	variable seq
	incr seq

	set top .view$seq
	
	if {[info exists ::gorilla::toplevel($top)]} {
		
		wm deiconify $top
		
	} else {
	
		toplevel $top
		wm title $top [ mc "View Login" ]
		set ::gorilla::toplevel($top) $top
		wm protocol $top WM_DELETE_WINDOW "gorilla::DestroyDialog $top"
		
		# position the view windows in a somehow stacky order ... to be improved
		set xpos 100
		set ypos 200
		set diff [expr $rn * 15]
		wm geometry $top "+[incr xpos $diff]+[incr ypos $diff]"
		
		set if [ ttk::frame $top.if -padding {5 5} ]
		
		foreach {child childname} { group Group title Title url URL 
						user Username pass Password 
						lpc {Last Password Change}
						mod {Last Modified} } {
			
			ttk::label $if.${child}L -text [mc ${childname}]:
			ttk::label $if.${child}E -width 40 -background white
	
			grid $if.${child}L $if.${child}E -sticky ew -pady 5
			
		}
		
		ttk::label $if.notesL -text [mc Notes]:
		ttk::label $if.notesE -width 40 -background white \
			-wraplength [expr {40 * [font measure "Helvetica 10" 0]}]
	
		grid $if.notesL $if.notesE -sticky ew -pady 5                
	
		if {[$::gorilla::db existsRecord $rn]} {
			if {[$::gorilla::db existsField $rn 2]} {
				$if.groupE configure -text [$::gorilla::db getFieldValue $rn 2]
			}
			if {[$::gorilla::db existsField $rn 3]} {
				$if.titleE configure -text [$::gorilla::db getFieldValue $rn 3]
			}
			if {[$::gorilla::db existsField $rn 4]} {
				$if.userE configure -text [$::gorilla::db getFieldValue $rn 4]
			}
			if {[$::gorilla::db existsField $rn 5]} {
				$if.notesE configure -text [$::gorilla::db getFieldValue $rn 5]
			}
			if {[$::gorilla::db existsField $rn 6]} {
				# $if.passE configure -text [$::gorilla::db getFieldValue $rn 6]
				$if.passE configure -text "********"
			}
			if {[$::gorilla::db existsField $rn 8]} {
				$if.lpcE configure -text \
					[clock format [$::gorilla::db getFieldValue $rn 8] \
					-format "%Y-%m-%d %H:%M:%S"]
			}
			if {[$::gorilla::db existsField $rn 12]} {
				$if.modE configure -text \
					[clock format [$::gorilla::db getFieldValue $rn 12] \
					-format "%Y-%m-%d %H:%M:%S"]
			}
			if {[$::gorilla::db existsField $rn 13]} {
				$if.urlE configure -text [$::gorilla::db getFieldValue $rn 13]
			}
		}
	
		set bf [ ttk::frame $top.bf -padding {10 10} ]
		
		
		ttk::button $bf.close -text [mc "Close"] -command "gorilla::DestroyDialog $top"
		ttk::button $bf.showpassw -text [mc "Show Password"] \
			-command [ list ::gorilla::ViewEntryShowPWHelper $bf.showpassw $if.passE $rn ]
		
		pack $bf.showpassw -side top -fill x
		pack $bf.close -side top -fill x -pady 5
		
		pack $if -side left -expand true -fill both
		pack $bf -side left -expand true -fill y
	}
}

#
# ----------------------------------------------------------------------
# A helper proc to make the show password button an actual toggle button
# ----------------------------------------------------------------------
#

proc gorilla::ViewEntryShowPWHelper { button entry rn } {
  if { [ $button cget -text ] eq [ mc "Show Password" ] } {
    $entry configure -text [$::gorilla::db getFieldValue $rn 6]
    $button configure -text [ mc "Hide Password" ]
  } else {
    $entry configure -text "********"
    $button configure -text [ mc "Show Password" ]
  }

} ; # end proc gorilla::ViewEntryShowPWHelper

#
# ----------------------------------------------------------------------
# Debugging for the Mac OS
# ----------------------------------------------------------------------
#

proc gorilla::writeToLog {logfile message} {
	# mac Abfrage
	set log "[clock format [clock seconds] -format %b\ %d\ %H:%M:%S] \
		\"Password Gorilla\": $message"
		
	if [file exists $logfile] {
		# puts "$logfile exists"
		set filehandler [open $logfile a+]
		puts $filehandler $log
		close $filehandler
	} else {
		puts "$logfile does not exist or no access permissions"
		puts $log
	}
}

proc psn_Delete {argv argc} {
	# debugging
	# gorilla::writeToLog $::gorilla::logfile "argv: $argv"
	
	set index 0
	set new_argv ""
	
	while { $index < $argc } {
		if {[string first "psn" [lindex $argv $index]] == -1} { 
			lappend new_argv [lindex $argv $index]
		}
		incr index
	}
	# gorilla::writeToLog $::gorilla::logfile "Gefilteter argv: $new_argv"
	return $new_argv
}

proc gorilla::msg { message } {
	tk_messageBox -type ok -icon info -message $message
}

#
# ----------------------------------------------------------------------
# Init
# ----------------------------------------------------------------------
#

# If we want some error logging
# set logfile "/home/dia/Projekte/tcl/console.log"
set ::gorilla::logfile "/private/var/log/console.log"

if {[tk windowingsystem] == "aqua"} {
	set argv [psn_Delete $argv $argc]

	proc ::tk::mac::ShowPreferences {} {
		if { ![info exists ::gorilla::fileName] || $::gorilla::fileName eq "" } {
			return
		}
		gorilla::PreferencesDialog
	}
	proc ::tk::mac::Quit {} {
    gorilla::Exit
	}

}
	
proc usage {} {
		puts stdout "usage: $::argv0 \[Options\] \[<database>\]"
		puts stdout "	Options:"
		puts stdout "		--rc <name>	 Use <name> as configuration file (not the Registry)."
		puts stdout "		--norc				Do not use a configuration file (or the Registry)."
		puts stdout "		<database>		Open <database> on startup."
}

if {$::gorilla::init == 0} {
	if {[string first "-norc" $argv0] != -1} {
		set ::gorilla::preference(norc) 1
	}

	set haveDatabaseToLoad 0
	set databaseToLoad ""

	# set argc [llength $argv]	;# obsolete

	for {set i 0} {$i < $argc} {incr i} {
		switch -- [lindex $argv $i] {
			--norc -
			-norc {
				set ::gorilla::preference(norc) 1
			}
			--rc -
			-rc {
				if {$i+1 >= $argc} {
					puts stderr "Error: [lindex $argv $i] needs a parameter."
					exit 1
				}
				incr i
				set ::gorilla::preference(rc) [lindex $argv $i]
			}
			--help {
				usage
				exit 0
			}
			default {
				if {$haveDatabaseToLoad} {
					usage
					exit 0
				}
				set haveDatabaseToLoad 1
				set databaseToLoad [lindex $argv $i]
			}
		}
	}
}
	gorilla::Init
	gorilla::LoadPreferences
	gorilla::InitGui
	set ::gorilla::init 1

	if {$haveDatabaseToLoad} {
		set action [gorilla::Open $databaseToLoad]
	} else {
		set action [gorilla::Open]
	}

	if {$action == "Cancel"} {
		destroy .
		exit		
	}

	wm deiconify .
	raise .
	update

	# exec say [mc "Welcome to the Password Gorilla."]	;# für MacOS
	set ::gorilla::status [mc "Welcome to the Password Gorilla."]
