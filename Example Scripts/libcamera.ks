@LAZYGLOBAL off.

// libcamera.ks

// All functions check to ensure the stock camera addon is installed.  If not,
// they return silently.  This allows you to include this script in a suite,
// even if the addon is not installed.  This is intended as a code portability
// feature.  For library scripts I recommend defining additional functions
// which in turn call the functions in this library, allowing other scripts to
// call these functions while not knowing that the script has been run in the
// current program session.  Like this:
// function exenode_slerpCameraPosition {
// 	parameter pos, dt is 10.
// 	if defined libcamera_camera {
// 		slerpCameraPosition(pos, dt).
// 	}
// }

if (not (defined libcamera_camera)) and addons:available("camera") {
	// defining global variables to store state information
	// due to the definition and avaiabilty checks above, these variables canceled
	// also serve as a way to detect that the stock camera addon is installed.
	global libcamera_camera is addons:camera:flightcamera.
	global libcamera_doRotation is false.
	global libcamera_doSlerp is false.
	global libcamera_rotationPeriod is 120.
	global libcamera_rotationRate is 0.
	global libcamera_lastMissionTime is -1.
	global libcamera_lastHdg is libcamera_camera:camerahdg.
	global libcamera_lastPitch is libcamera_camera:camerapitch.
}

function setCameraPosition {
	parameter pos.
	// imediately set the camera position to the vector pos
	if defined libcamera_camera {
		set libcamera_camera:cameraposition to pos.
	}
}

function slerpCameraPosition {
	parameter pos, dt is 10.
	// smoothly move the camera from teh current position to the vector pos over
	// the course of dt number of seconds
	if defined libcamera_camera {
		global libcamera_slerpStartUt is time:seconds.
		global libcamera_slerpEndUt is libcamera_slerpStartUt + dt.
		global libcamera_slerpStartPos is libcamera_camera:cameraposition.
		global libcamera_slerpEndPos is pos.
		if not (defined libcamera_slerpReEnableRotation) { global libcamera_slerpReEnableRotation is false. }
		if libcamera_doRotation {
			set libcamera_slerpReEnableRotation to true.
			disableCameraRotation().
		}
		if not libcamera_doSlerp {
			set libcamera_doSlerp to true.
			on time:seconds {
				local ut is time:seconds.
				if ut >= libcamera_slerpEndUt {
					set libcamera_camera:cameraposition to libcamera_slerpEndPos.
					if libcamera_slerpReEnableRotation {
						enableCameraRotation().
						set libcamera_slerpReEnableRotation to false.
					}
					set libcamera_doSlerp to false.
					return libcamera_doSlerp.
				}
				local ratio is 1 - (libcamera_slerpEndUt - ut) / (libcamera_slerpEndUt - libcamera_slerpStartUt).
				local axis is vcrs(libcamera_slerpStartPos, libcamera_slerpEndPos):normalized.
				local angle is vang(libcamera_slerpStartPos, libcamera_slerpEndPos).
				local rot is angleaxis(angle * ratio, axis).
				local mag is (libcamera_slerpEndPos:mag - libcamera_slerpStartPos:mag) * ratio + libcamera_slerpStartPos:mag.
				set libcamera_camera:cameraposition to (libcamera_slerpStartPos * rot):normalized * mag.
				return libcamera_doSlerp.
			}
		}
	}
}

function setCameraHeading {
	parameter hdg.
	// set the camera's heading value, which is the rotation about the camera's
	// frame of reference "up".  That is to say heading is aligned with the
	// left/righ keys for camera control, and exact travel depends on the
	// current camera mode.
	if defined libcamera_camera {
		set libcamera_camera:camerahdg to hdg.
	}
}

function setCameraPitch {
	parameter pitch.
	// set the camera's pitch value, which is the rotation about the camera's
	// frame of reference "starboard".  That is to say heading is aligned with the
	// up/down keys for camera control, and exact travel depends on the
	// current camera mode.
	if defined libcamera_camera {
		set libcamera_camera:camerapitch to pitch.
	}
}

function setCameraDistance {
	parameter dist.
	// set the distance the camera is located from the focal point to the value
	// dist.  This is essentially the magnitude of the position vector.
	if defined libcamera_camera {
		set libcamera_camera:cameradistance to dist.
	}
}

function setCameraMode {
	parameter mode.
	// set the current camera mode to the given string mode.  An exception is
	// thrown if an invalid string is used, so there are helper functions below
	// to select specific common modes.
	if defined libcamera_camera {
		set libcamera_camera:cameramode to mode.
	}
}

function setCameraFree {
	// set the current camera mode to "free"
	setCameraMode("FREE").
}

function setCameraOrbit {
	// set the current camera mode to "orbital"
	setCameraMode("ORBITAL").
}

function setCameraOrbital {
	// set the current camera mode to "orbital"
	setCameraMode("ORBITAL").
}

function enableCameraRotation {
	parameter period is 0.
	// enable automated camera rotation about up axis of the current reference
	// frame.  One revolution will take the given period, which defaults to two
	// minutes.  If you don't want to change the rotational period **from the
	// previous setting** pass the value 0.  Passing a negative value will
	// reverse directions
	if defined libcamera_camera {
		if period = 0 set period to libcamera_rotationPeriod.
		else set libcamera_rotationPeriod to period.
		set libcamera_rotationRate to 360 / period.
		if not libcamera_doRotation {
			set libcamera_doRotation to true.
			on missiontime {
				local hdg is libcamera_camera:camerahdg + libcamera_rotationRate * min(missiontime - libcamera_lastMissionTime, 0.04).
				set libcamera_camera:camerahdg to hdg.
				set libcamera_lastHdg to hdg.
				return libcamera_doRotation.
			}
		}
	}
}

function disableCameraRotation {
	// disable the automated camera rotation if enabled
	if (defined libcamera_doRotation){
		set libcamera_doRotation to false.
	}
}

function toggleCameraRotation {
	// enables camera rotation if already disabled, or disables if already enabled
	if (defined libcamera_doRotation) and libcamera_doRotation { disableCameraRotation(). }
	else enableCameraRotation().
}

function setCameraLaunchPosition {
	// This function waits for the camera to stop moving (when you first fly a
	// a vessel, KSP pans towards the center of mass) before slerping the
	// camera position towards the VAB.  The magnitude of the vector depends
	// on the radar altitude, as a means for ensuring the vessel is visible.
	// the slerp time is set to 8.5s, to match a common count down of 10s.  The
	// function can be revised to accept a duration and/or distance parameter.
	if defined libcamera_camera {
		local oldPosition is libcamera_camera:cameraposition.
		wait 0.
		until (libcamera_camera:cameraposition - oldPosition):mag < 0.01 {
			set oldPosition to libcamera_camera:cameraposition.
			wait 0.5.
		}
		local unit is -vcrs(up:vector, north:vector).
		local geo is body:geopositionof(unit * alt:radar * 4).
		local newPos is geo:altitudeposition(geo:terrainheight + 10).
		slerpCameraPosition(newPos, 8.5).
	}
}
