var/list/camera_names=list()
/obj/machinery/camera
	name = "security camera"
	desc = "It's used to monitor rooms."
	icon = 'icons/obj/monitors.dmi'
	icon_state = "camera"
	use_power = 2
	idle_power_usage = 5
	active_power_usage = 10
	layer = 5

	var/datum/wires/camera/wires = null // Wires datum
	var/list/network = list("SS13")
	var/c_tag = null
	var/c_tag_order = 999
	var/status = 1.0
	anchored = 1.0
	var/invuln = null
	var/bugged = 0
	var/obj/item/weapon/camera_assembly/assembly = null
	var/light_on = 0

	machine_flags = SCREWTOGGLE //| WIREJACK Needs work

	//OTHER

	var/view_range = 7
	var/short_range = 2

	var/light_disabled = 0
	var/alarm_on = 0
	var/busy = 0

/obj/machinery/camera/update_icon()
	var/EMPd = stat & EMPED
	var/deactivated = !status
	var/camtype = "camera"
	if(assembly)
		camtype = isXRay() ? "xraycam" : "camera" // Thanks to Krutchen for the icons.

	if (deactivated)
		icon_state = "[camtype]1"
	else if (EMPd)
		icon_state = "[camtype]emp"
	else
		icon_state = "[camtype]"

/obj/machinery/camera/New()
	wires = new(src)

	assembly = new(src)
	assembly.state = 4

	if(!src.network || src.network.len < 1)
		if(loc)
			error("[src.name] in [get_area(src)] (x:[src.x] y:[src.y] z:[src.z] has errored. [src.network?"Empty network list":"Null network list"]")
		else
			error("[src.name] in [get_area(src)]has errored. [src.network?"Empty network list":"Null network list"]")
		ASSERT(src.network)
		ASSERT(src.network.len > 0)

	if(!c_tag)
		name_camera()
	..()
	if(adv_camera && adv_camera.initialized && !(src in adv_camera.camerasbyzlevel["[z]"]))
		adv_camera.update(z, 0, src, adding=1)

/obj/machinery/camera/proc/name_camera()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/name_camera() called tick#: [world.time]")
	var/area/A=get_area(src)
	var/basename=A.name
	var/nethash=english_list(network)
	var/suffix = 0
	while(!suffix || nethash+c_tag in camera_names)
		c_tag = "[basename]"
		if(suffix)
			c_tag += " [suffix]"
		suffix++
	camera_names[nethash+c_tag]=src

/obj/machinery/camera/change_area(oldarea, newarea)
	var/nethash=english_list(network)
	camera_names[nethash+c_tag]=null
	..()
	if(name != replacetext(name,oldarea,newarea))
		name_camera()

/obj/machinery/camera/Destroy()
	deactivate(null, 0) //kick anyone viewing out
	if(assembly)
		qdel(assembly)
		assembly = null
	wires = null
	cameranet.removeCamera(src) //Will handle removal from the camera network and the chunks, so we don't need to worry about that
	for(var/key in camerasbyzlevel)
		camerasbyzlevel[key] -= src
	..()

/obj/machinery/camera/emp_act(severity)
	if(!isEmpProof())
		if(prob(100/severity))
			var/list/previous_network = network
			network = list()
			cameranet.removeCamera(src)
			stat |= EMPED
			set_light(0)
			triggerCameraAlarm()
			update_icon()
			spawn(900)
				network = previous_network
				stat &= ~EMPED
				cancelCameraAlarm()
				update_icon()
				if(can_use())
					cameranet.addCamera(src)
					adv_camera.update(z, 0, src, adding=1)
			for(var/mob/O in mob_list)
				if (istype(O.machine, /obj/machinery/computer/security))
					var/obj/machinery/computer/security/S = O.machine
					if (S.current == src)
						O.unset_machine()
						O.reset_view(null)
						O << "The screen bursts into static."
			..()


/obj/machinery/camera/ex_act(severity)
	if(src.invuln)
		return
	else
		..(severity)
	return

/obj/machinery/camera/blob_act()
	qdel(src)
	return

/obj/machinery/camera/proc/setViewRange(var/num = 7)
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/setViewRange() called tick#: [world.time]")
	src.view_range = num
	cameranet.updateVisibility(src, 0)

/obj/machinery/camera/shock(var/mob/living/user)
	if(!istype(user))
		return
	user.electrocute_act(10, src)

/obj/machinery/camera/attack_paw(mob/living/carbon/alien/humanoid/user as mob)
	if(!istype(user))
		return
	if(!status)
		return
	status = 0
	update_icon()
	visible_message("<span class='warning'>\The [user] slashes at [src]!</span>")
	playsound(get_turf(src), 'sound/weapons/slash.ogg', 100, 1)
	add_hiddenprint(user)
	deactivate(user,0)

/obj/machinery/camera/attackby(W as obj, mob/living/user as mob)

	// DECONSTRUCTION
	if(istype(W, /obj/item/weapon/screwdriver))
		//user << "<span class='notice'>You start to [panel_open ? "close" : "open"] the camera's panel.</span>"
		//if(toggle_panel(user)) // No delay because no one likes screwdrivers trying to be hip and have a duration cooldown
		togglePanelOpen(W, user, icon_state, icon_state)

	else if((istype(W, /obj/item/weapon/wirecutters) || istype(W, /obj/item/device/multitool)) && panel_open)
		wires.Interact(user)

	else if(istype(W, /obj/item/weapon/weldingtool) && wires.CanDeconstruct())
		if(weld(W, user))
			if(assembly)
				assembly.state = 1
				assembly.loc = src.loc
				assembly = null

			qdel(src)

	// Upgrades!
	else if(is_type_in_list(W, assembly.possible_upgrades)) // Is a possible upgrade
		if (is_type_in_list(W, assembly.upgrades))
			user << "The camera already has \a [W] inside!"
			return
		if (!panel_open)
			user << "You can't reach into the camera's circuitry while the maintenance panel is closed."
			return
		if (!wires.CanDeconstruct())
			user << "You can't reach into the camera's circuitry with the wires on the way."
			return
		user << "You attach the [W] into the camera's inner circuits."
		assembly.upgrades += W
		user.drop_item(W, src)
		update_icon()
		return

	// Taking out upgrades
	else if(iscrowbar(W))
		if (!panel_open)
			user << "You can't reach into the camera's circuitry while the maintenance panel is closed."
			return
		if (!wires.CanDeconstruct())
			user << "You can't reach into the camera's circuitry with the wires on the way."
			return
		if (assembly.upgrades.len)
			var/obj/U = locate(/obj) in assembly.upgrades
			if(U)
				user << "You unattach \the [U] from the camera."
				playsound(get_turf(src), 'sound/items/Crowbar.ogg', 50, 1)
				U.loc = get_turf(src)
				assembly.upgrades -= U
				update_icon()
			return
		else //Camera deconned, no upgrades
			user << "The camera is firmly welded to the wall." //User might be trying to deconstruct the camera with a crowbar, let them know what's wrong
			return

	// OTHER
	else if ((istype(W, /obj/item/weapon/paper) || istype(W, /obj/item/device/pda)) && isliving(user))
		user.delayNextAttack(5)
		var/mob/living/U = user
		var/obj/item/weapon/paper/X = null
		var/obj/item/device/pda/P = null

		var/itemname = ""
		var/info = ""
		if(istype(W, /obj/item/weapon/paper))
			X = W
			itemname = X.name
			info = X.info
		else
			P = W
			itemname = P.name
			info = P.notehtml
		U << "You hold \a [itemname] up to the camera ..."
		for(var/mob/living/silicon/ai/O in living_mob_list)
			if(!O.client) continue
			if(U.name == "Unknown") O << "<span class='name'>[U]</span> holds \a [itemname] up to one of your cameras ..."
			else O << "<span class='name'><a href='byond://?src=\ref[O];track2=\ref[O];track=\ref[U]'>[U]</a></span> holds \a [itemname] up to one of your cameras ..."
			O << browse(text("<HTML><HEAD><TITLE>[]</TITLE></HEAD><BODY><TT>[]</TT></BODY></HTML>", itemname, info), text("window=[]", itemname))
		for(var/mob/O in player_list)
			if (istype(O.machine, /obj/machinery/computer/security))
				var/obj/machinery/computer/security/S = O.machine
				if (S.current == src)
					O << "[U] holds \a [itemname] up to one of the cameras ..."
					O << browse(text("<HTML><HEAD><TITLE>[]</TITLE></HEAD><BODY><TT>[]</TT></BODY></HTML>", itemname, info), text("window=[]", itemname))
	else
		..()
	return

/obj/machinery/camera/attack_pai(mob/user as mob)
	wirejack(user)

/obj/machinery/camera/proc/deactivate(user as mob, var/choice = 1)
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/deactivate() called tick#: [world.time]")
	if(choice==1)
		status = !( src.status )
		update_icon()
		if (!(src.status))
			if(user)
				visible_message("<span class='warning'>[user] has deactivated [src]!</span>")
				add_hiddenprint(user)
			else
				visible_message("<span class='warning'> \The [src] deactivates!</span>")
			playsound(get_turf(src), 'sound/items/Wirecutter.ogg', 100, 1)
			add_hiddenprint(user)
		else
			if(user)
				visible_message("<span class='warning'> [user] has reactivated [src]!</span>")
				add_hiddenprint(user)
			else
				visible_message("<span class='warning'> \the [src] reactivates!</span>")
			playsound(get_turf(src), 'sound/items/Wirecutter.ogg', 100, 1)
			add_hiddenprint(user)
	// now disconnect anyone using the camera
	//Apparently, this will disconnect anyone even if the camera was re-activated.
	//I guess that doesn't matter since they can't use it anyway?
	for(var/mob/O in player_list)
		if (istype(O.machine, /obj/machinery/computer/security))
			var/obj/machinery/computer/security/S = O.machine
			if (S.current == src)
				O.unset_machine()
				O.reset_view(null)
				O << "The screen bursts into static."
	if(choice && can_use()) //camera reactivated
		adv_camera.update(z, 0, src, adding=1)
	else //either deactivated OR being destroyed
		adv_camera.update(z, 0, src, adding=2)

/obj/machinery/camera/proc/triggerCameraAlarm()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/triggerCameraAlarm() called tick#: [world.time]")
	if(!alarm_on)
		adv_camera.update(z, 0, src, adding=4) //1 is alarming, 0 is nothing wrong
	alarm_on = 1
	for(var/mob/living/silicon/S in mob_list)
		S.triggerAlarm("Camera", areaMaster, list(src), src)


/obj/machinery/camera/proc/cancelCameraAlarm()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/cancelCameraAlarm() called tick#: [world.time]")
	if(alarm_on)
		adv_camera.update(z, 0, src, adding=4) //1 is alarming, 0 is nothing wrong
	alarm_on = 0
	for(var/mob/living/silicon/S in mob_list)
		S.cancelAlarm("Camera", areaMaster, list(src), src)

/obj/machinery/camera/proc/can_use()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/can_use() called tick#: [world.time]")
	if(!status)
		return 0
	if(stat & EMPED)
		return 0
	return 1

/obj/machinery/camera/proc/can_see()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/can_see() called tick#: [world.time]")
	var/list/see = null
	var/turf/pos = get_turf(src)
	if(isXRay())
		see = range(view_range, pos)
	else
		see = get_hear(view_range, pos)
	return see

/atom/proc/auto_turn()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/atom/proc/auto_turn() called tick#: [world.time]")
	//Automatically turns based on nearby walls.
	var/turf/simulated/wall/T = null

	for (var/direction in cardinal)
		T = get_ranged_target_turf(src, direction, 1)

		if (istype(T))
			dir = reverse_direction(direction)
			break

//Return a working camera that can see a given mob
//or null if none
/proc/seen_by_camera(var/mob/M)
	//writepanic("[__FILE__].[__LINE__] (no type)([usr ? usr.ckey : ""])  \\/proc/seen_by_camera() called tick#: [world.time]")
	for(var/obj/machinery/camera/C in oview(4, M))
		if(C.can_use())	// check if camera disabled
			return C
			break
	return null

/proc/near_range_camera(var/mob/M)

	//writepanic("[__FILE__].[__LINE__] (no type)([usr ? usr.ckey : ""])  \\/proc/near_range_camera() called tick#: [world.time]")

	for(var/obj/machinery/camera/C in range(4, M))
		if(C.can_use())	// check if camera disabled
			return C
			break

	return null

/obj/machinery/camera/proc/weld(var/obj/item/weapon/weldingtool/WT, var/mob/user)

	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/obj/machinery/camera/proc/weld() called tick#: [world.time]")

	if(busy)
		return 0
	if(!WT.isOn())
		return 0

	// Do after stuff here
	user << "<span class='notice'>You start to weld the [src].</span>"
	playsound(get_turf(src), 'sound/items/Welder.ogg', 50, 1)
	WT.eyecheck(user)
	busy = 1
	if(do_after(user, src, 100))
		busy = 0
		if(!WT.isOn())
			return 0
		return 1
	busy = 0
	return 0

/obj/machinery/camera/wirejack(var/mob/living/silicon/pai/P)
	if(..())
		P.set_machine(P)
		P.current = src
		P.reset_view(src)
		return 1
	return 0
