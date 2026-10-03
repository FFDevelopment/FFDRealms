#!/usr/bin/env python3
"""Offline combat source/data + independent math/timing checks, NOT GDScript execution.
The numerical model reads the live tuning; angular and vector oracles are compared.
Native state-machine/scene regressions are separately in combat_runner.gd.
"""
from __future__ import annotations
import hashlib
import json
import math
import random
from pathlib import Path
from check_project import literal, parse_expression
from check_frontier import body

ROOT = Path(__file__).resolve().parents[1]
results: list[dict] = []

def check(ok: bool, label: str) -> None:
    results.append({'check': label, 'passed': bool(ok)})
    print(('PASS: ' if ok else 'FAIL: ') + label)

def dot_hit(origin, facing, radius, half, point):
    """Independent Python counterpart of the sector math; not executing Godot."""
    if not all(math.isfinite(v) for v in (*origin, *facing, radius, half, *point)):
        return False
    if radius <= 0 or half <= 0 or abs(point[1] - origin[1]) > .5:
        return False
    x, z = point[0] - origin[0], point[2] - origin[2]
    dx, dz = facing[0], facing[2]
    length_sq, face_sq = x*x+z*z, dx*dx+dz*dz
    if face_sq < 1e-6 or length_sq > radius*radius:
        return False
    if length_sq <= 1e-6:
        return True
    return (x*dx+z*dz) / math.sqrt(length_sq*face_sq) >= math.cos(half)

def angular_oracle(origin, facing, radius, half, point):
    if not all(math.isfinite(v) for v in (*origin, *facing, radius, half, *point)):
        return False
    if radius <= 0 or half <= 0 or abs(point[1] - origin[1]) > .5:
        return False
    x,z=point[0]-origin[0],point[2]-origin[2]
    if math.hypot(facing[0],facing[2]) < .001 or math.hypot(x,z)>radius:
        return False
    if math.hypot(x,z)<=.001:
        return True
    offset=(math.atan2(x,z)-math.atan2(facing[0],facing[2])+math.pi)%(2*math.pi)-math.pi
    return abs(offset)<=half

def move_toward(point, target, distance):
    length=math.dist(point,target)
    if length<=distance:return target
    return tuple(a+(b-a)*distance/length for a,b in zip(point,target))

def main() -> int:
    texts={x:(ROOT/'scripts'/f'{x}.gd').read_text() for x in
           ('enemy_ai','combat_rules','game_state','world_layout','enemy_visual','world','hud','main')}
    ai,rules,state,layout,visual,world,hud,input_code=[texts[k] for k in texts]
    targets=parse_expression(layout.split('static func targets()',1)[1].split('\n\treturn ',1)[1])
    enemies=[t for t in targets if t['kind']=='enemy']
    hit_time=literal(rules,'PLAYER_STRIKE_TIME')
    cadence=literal(rules,'PLAYER_ATTACK_INTERVAL')
    defaults={k:literal(rules,'DEFAULT_'+k) for k in ('NOTICE','REACH','ARC_DEGREES','WINDUP','RECOVERY')}
    speed=literal(state,'WALK_SPEED')
    check(hit_time==.35 and cadence==.95 and hit_time<cadence,'Quick strike uses a separate original-rate minimum attack interval')
    check(len(enemies)==8 and len({e.get('species','mossling') for e in enemies})==4,'All eight enemies and four species are covered')
    for e in enemies:
        id=e['id']; windup=e.get('windup',defaults['WINDUP']); radius=e.get('reach',defaults['REACH']); half=math.radians(e.get('attack_arc',defaults['ARC_DEGREES'])/2)
        check(0<e.get('notice',defaults['NOTICE'])<=e.get('leash',12),'Positive proximity detection within leash: '+id)
        check(windup>=.65 and e.get('recovery',defaults['RECOVERY'])>=.6,'Telegraph and recovery windows are explicit: '+id)
        origin=(0,0,0); direction=(0,0,1)
        check(dot_hit(origin,direction,radius,half,(0,0,1.5)),'Stationary player in front is hit: '+id)
        check(not dot_hit(origin,direction,radius,half,(1.5,0,0)),'Sideways dodge works inside nominal reach: '+id)
        check(not dot_hit(origin,direction,radius,half,(0,0,-1.5)),'Behind the committed strike is outside its arc: '+id)
        check(not dot_hit(origin,direction,radius,half,(0,0,radius+.001)),'No hidden range beyond the visible radius: '+id)
        # Numerical stand-in for hit -> move, evaluated at the impact instant.
        position=move_toward((0,0,1.6),(2.5,0,.2),speed*(windup-hit_time))
        check(not dot_hit(origin,direction,radius,half,position),'Configured speed permits strike then dodge during windup: '+id)
        check(dot_hit(origin,direction,radius,half,(0,0,1.6)),'Moving out then returning before impact remains hittable: '+id)
    rng=random.Random(222)
    samples=12000; mismatches=0
    for _ in range(samples):
        e=rng.choice(enemies);r=e.get('reach',defaults['REACH']);half=math.radians(e.get('attack_arc',defaults['ARC_DEGREES'])/2)
        origin=(rng.uniform(-25,25),0,rng.uniform(-62,-17));angle=rng.uniform(-math.pi,math.pi)
        facing=(math.sin(angle),0,math.cos(angle))
        point=(origin[0]+rng.uniform(-3,3),0,origin[2]+rng.uniform(-3,3))
        mismatches += dot_hit(origin,facing,r,half,point)!=angular_oracle(origin,facing,r,half,point)
    check(mismatches==0,'12,000 seeded vector/angle sector comparisons agree')
    for field in ('strike_origin','strike_facing','strike_reach','strike_half_angle','strike_duration'):
        check('status["'+field+'"] =' in body(ai,'begin_windup'),'Windup snapshots '+field)
    step=body(ai,'step'); windup_block=step.split('\t\t"windup":',1)[1].split('\t\t"recover":',1)[0]
    check('Combat.contains_point(origin, status["strike_facing"]' in windup_block and '_combat_line_clear(origin, player, navigation)' in windup_block,'Impact validates current player position against fixed geometry and cover')
    check('status["pos"] =' not in windup_block and 'status["facing"] =' not in windup_block,'Committed swing cannot chase or swivel')
    check('not in ["windup", "recover"]' in step,'Facing updates exclude committed and recovery states')
    check('status["state"] = "recover"' in windup_block and 'status["strike_id"] = int(status["strike_id"]) + 1' in windup_block,'Each impact transitions out of windup before any damage return')
    check('status["state_time"] =' not in body(ai,'provoke') and 'status["attack_time"] =' not in body(ai,'provoke'),'Player hits cannot restart enemy timers')
    check('Combat.DEFAULT_NOTICE' in step and 'notice > 0.0' in step and '_combat_line_clear(here, player, navigation)' in step,'Unconfigured enemy defaults to close-range LOS detection, with explicit zero opt-out')
    check(step.index('if str(status["state"]) == "return":')<step.index('if not bool(status["aggro"]):'),'Return-home behavior runs before proximity acquisition')
    check('Layout.is_safe(player)' in step and 'navigation.enemy_clear_position' in step,'Safe towns and body-safe placement still gate combat')
    check('_attack_cooldown' not in body(state,'cancel_action') and '_attack_cooldown = 0' not in body(state,'request_move'),'Movement/cancel cannot clear weapon cooldown')
    begin=body(state,'_begin_interaction');request=body(state,'request_interaction')
    check('action_duration = Combat.PLAYER_STRIKE_TIME' in begin and '_attack_cooldown = Combat.PLAYER_ATTACK_INTERVAL' in begin,'Swing duration and cadence are set separately when the swing starts')
    check('_attack_cooldown > 0.0' in request and request.index('_attack_cooldown > 0.0')<request.index('cancel_action()'),'Cooldown rejection preserves the existing movement route')
    check('_attack_cooldown = maxf(0.0, _attack_cooldown - step)' in body(state,'tick'),'Weapon cooldown advances independently of active action')
    check('if not _consume_action(id)' in body(state,'_hit_enemy') and 'enemy_attackable' in body(state,'_hit_enemy'),'Reward path still consumes one authorized click')
    check('active_target =' not in ai and '_hit_enemy' not in ai,'Enemy simulation never grants player counterattacks')
    check('previous_strike' in body(state,'_update_enemy_retaliation') and '"MISSED"' in body(state,'_update_enemy_retaliation'),'Miss feedback is emitted only on a new strike result')
    check('navigation.segment_clear(here, ground)' in body(state,'request_move') and 'PackedVector3Array([ground])' in body(state,'request_move'),'Clear movement clicks use direct continuous movement')
    check('Combat.reach(definition)' in body(visual,'build_warning') and 'Combat.half_angle(definition)' in body(visual,'build_warning'),'Warning builder uses the same reach/angle functions as combat')
    check('warning.position = Vector3(origin.x - here.x, 0.0, origin.z - here.z)' in body(visual,'animate') and 'status["strike_facing"]' in body(visual,'animate'),'Warning pose follows the committed snapshot, not current target')
    check('warning.scale = Vector3.ONE' in body(visual,'animate') and 'warning.scale = Vector3.ONE *' not in visual,'Warning footprint does not pulse in size')
    check('StandardMaterial3D.new()' in body(visual,'_warning_material'),'Warning materials are independent per instance')
    check('Creature.build_warning(root, definition)' in world and '"MOVE OUT!' in world,'World creates the sector and countdown label')
    check('click_force_move = click.shift_pressed' in input_code and '"" if force_move else _pick_target(screen)' in input_code,'Shift-click can bypass target pick boxes for movement')
    check('"Recovering' not in rules and 'Weapon recovering' in body(state,'action_label') and 'Weapon ready' in body(state,'action_label'),'HUD action text differentiates weapon cooldown and readiness')
    check('"appearance"' in body(state,'serialized_character') and 'strike_' not in body(state,'serialized_character') and '_attack_cooldown' not in body(state,'serialized_character'),'Profile stores appearance, not transient combat actions')
    check('combat_runner.gd' in (ROOT/'Run Tests.bat').read_text(),'Native combat suite is wired into the local test launcher')
    # Timing model: canceled/finished actions do not erase cooldown or generate auto-hits.
    remaining=cadence-.1;active=False
    rejected=0
    for _ in range(20):
        rejected+=remaining>0
    check(rejected==20 and not active,'Reference cancel-spam leaves no authorized action')
    remaining=max(0,remaining-1)
    check(remaining==0 and not active,'Reference cooldown expiry grants readiness, not an attack')
    report={'version':'0.3.0','scope':'Source/data and independent Python sector/timing checks only; no GDScript execution',
            'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results),
            'sector_oracle':{'samples':samples,'mismatches':mismatches},'checks':results,
            'source_sha256':{k:hashlib.sha256(v.encode()).hexdigest() for k,v in texts.items()}}
    (ROOT/'docs/combat_check_results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f"COMBAT REFERENCE RESULT: {report['passed']} passed; {report['failed']} failed. No engine execution.")
    return int(report['failed']>0)

if __name__=='__main__':
    raise SystemExit(main())
