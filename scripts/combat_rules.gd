extends RefCounted
## Shared numbers and strike geometry for the simulation AND its warning mesh.
## A strike is a fixed sector on the ground, not a homing radius around a target.
const PLAYER_STRIKE_TIME: float = 0.35
const PLAYER_ATTACK_INTERVAL: float = 0.95
const DEFAULT_NOTICE: float = 3.5
const DEFAULT_REACH: float = 1.9
const DEFAULT_ARC_DEGREES: float = 110.0
const DEFAULT_WINDUP: float = 0.75
const DEFAULT_RECOVERY: float = 0.65

static func reach(definition: Dictionary) -> float:
	return maxf(0.1, float(definition.get("reach", DEFAULT_REACH)))

static func half_angle(definition: Dictionary) -> float:
	return deg_to_rad(clampf(float(definition.get("attack_arc", DEFAULT_ARC_DEGREES)), 20.0, 180.0) * 0.5)

static func windup(definition: Dictionary) -> float:
	return maxf(0.25, float(definition.get("windup", DEFAULT_WINDUP)))

static func recovery(definition: Dictionary) -> float:
	return maxf(0.25, float(definition.get("recovery", DEFAULT_RECOVERY)))

static func contains_point(origin: Vector3, direction: Vector3, radius: float, angle: float, point: Vector3) -> bool:
	if not origin.is_finite() or not direction.is_finite() or not point.is_finite():
		return false
	if not is_finite(radius) or not is_finite(angle) or radius <= 0.0 or angle <= 0.0:
		return false
	# All current combatants stand on the same ground plane; do not hit other floors.
	if absf(point.y - origin.y) > 0.5:
		return false
	var offset: Vector3 = Vector3(point.x - origin.x, 0, point.z - origin.z)
	var facing: Vector3 = Vector3(direction.x, 0, direction.z)
	if facing.length_squared() < 0.000001 or offset.length_squared() > radius * radius:
		return false
	# Standing on the attack origin is not a dodge exploit.
	if offset.length_squared() <= 0.000001:
		return true
	return facing.normalized().dot(offset.normalized()) >= cos(angle)
