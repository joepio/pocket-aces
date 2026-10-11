"""Real daemon + companion relay + Godot, on isolated ports and disposable profiles.
Requires Python websockets, Godot 4.5+, and current GameNight binaries.
No production profiles, room or library are changed.
"""
import argparse, asyncio, json, os, pathlib, subprocess, sys, tempfile, urllib.request, uuid
import websockets

ROOT = pathlib.Path(__file__).resolve().parents[1]

def request(base, path, data=None):
    req = urllib.request.Request(base+path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=5) as response:
        return json.load(response)

async def message(ws, predicate, seconds=12):
    async with asyncio.timeout(seconds):
        while True:
            data = json.loads(await ws.recv())
            if predicate(data): return data

async def main():
    p=argparse.ArgumentParser()
    p.add_argument('--daemon',required=True);p.add_argument('--web',required=True);p.add_argument('--godot',required=True)
    p.add_argument('--serve',action='store_true');p.add_argument('--fixture',default=str(pathlib.Path(tempfile.gettempdir())/'pocket-aces-fixture.json'))
    p.add_argument('--phone-test',action='store_true');p.add_argument('--screenshots',default=str(pathlib.Path(tempfile.gettempdir())/'pocket-aces-screenshots'))
    p.add_argument('--visible',action='store_true',help='Leave a real 3D game window open with --serve')
    p.add_argument('--windows-game',action='store_true',help='Run native Windows Godot from WSL against the WSL host')
    args=p.parse_args()
    children=[]
    with tempfile.TemporaryDirectory(prefix='pocket-aces-') as tmp:
        folder=pathlib.Path(tmp)
        library=folder/'library.json'
        library.write_text(json.dumps([{'id':'pocket-aces','title':'Pocket Aces','min_players':2,'max_players':6}]))
        env={k:v for k,v in os.environ.items() if not k.startswith(('GAMENIGHT','POCKET_ACES'))}
        env.update(GAMENIGHT_ADDR='127.0.0.1:18112',GAMENIGHT_WEB_ADDR='0.0.0.0:18113',GAMENIGHT_LIBRARY=str(library),GAMENIGHT_NO_PREWARM='1',GAMENIGHT_NO_LOBBY_WATCH='1',GAMENIGHT_DATA_DIR=str(folder/'data'),GAMENIGHT_PLAYER_MEMORY=str(folder/'memory.json'))
        logs=[]
        def start(name, command, extra=None):
            log=open(folder/(name+'.log'),'w');logs.append(log)
            child_env=env| (extra or {})
            if args.windows_game and name=='game':
                keys=[key for key in child_env if key.startswith(('GAMENIGHT','POCKET_ACES'))]
                child_env['WSLENV']=':'.join(keys)
            proc=subprocess.Popen(command,env=child_env,stdout=log,stderr=subprocess.STDOUT)
            children.append(proc)
            return proc
        try:
            start('daemon',[args.daemon,'127.0.0.1:18112'])
            start('web',[args.web])
            base='http://127.0.0.1:18113'
            for _ in range(80):
                try: await asyncio.to_thread(request,base,'/api/player-links');break
                except Exception: await asyncio.sleep(.25)
            async with websockets.connect('ws://127.0.0.1:18112') as overlay:
                await overlay.send(json.dumps({'type':'hello','role':'overlay'}))
                await message(overlay,lambda m:m['type']=='welcome')
                profiles=[]
                ids=[]
                for name in ['Clover','Peaches']:
                    profile=str(uuid.uuid4());profiles.append(profile)
                    await asyncio.to_thread(request,base,'/api/profiles',{'id':profile,'username':name,'skin_color':'#d7a778','avatar':''})
                    joined=await asyncio.to_thread(request,base,f'/api/profiles/{profile}/join',{})
                    assert joined.get('player_id'), joined
                    ids.append(joined['player_id'])
                game_path=str(ROOT)
                extra={'GAMENIGHT':'1','GAMENIGHT_GAME_ID':'pocket-aces','GAMENIGHT_LINKS_URL':'http://127.0.0.1:18113'}
                if args.windows_game:
                    game_path=subprocess.check_output(['wslpath','-w',str(ROOT)],text=True).strip()
                    extra['POCKET_ACES_COMPANION_ROOT']=str(ROOT/'phone')
                start('game',[args.godot]+([] if args.visible else ['--headless'])+['--path',game_path],extra)
                await asyncio.sleep(1.5)
                await overlay.send(json.dumps({'type':'set_playlist','entries':['pocket-aces']}))
                await message(overlay,lambda m:m.get('party',{}).get('active_session',{}).get('phase')=='running' if m.get('party',{}).get('active_session') else False)
                for _ in range(40):
                    current=await asyncio.to_thread(request,base,f'/api/companion?profile={profiles[0]}')
                    if current.get('url'):break
                    await asyncio.sleep(.1)
                assert current.get('game')=='pocket-aces',current
                try:
                    async with websockets.connect('ws://127.0.0.1:18113/api/companion/ws?profile=unknown&game=pocket-aces'):
                        raise AssertionError('Unlinked phone accepted')
                except websockets.exceptions.InvalidStatus as e:
                    assert e.response.status_code==403
                urls=[base+f'/play/pocket-aces/index.html?profile={pr}&game=pocket-aces' for pr in profiles]
                sockets=[]
                for profile in profiles:
                    sockets.append(await websockets.connect(f'ws://127.0.0.1:18113/api/companion/ws?profile={profile}&game=pocket-aces'))
                async def state(i):
                    await sockets[i].send(json.dumps({'action':'sync'}))
                    return await message(sockets[i],lambda m:m.get('type')=='state')
                views=[await state(0),await state(1)]
                assert all(v['setup']['waiting'] and not v['you']['cards'] and not v['actions'] and v['pot']==0 for v in views)
                await sockets[0].send(json.dumps({'action':'ready','ready':True}))
                one_ready=await message(sockets[0],lambda m:m.get('type')=='state' and m['setup']['count']==1)
                assert one_ready['setup']['waiting'] and one_ready['setup']['count']==1
                await sockets[0].close()
                disconnected=await message(sockets[1],lambda m:m.get('type')=='state' and m['setup']['count']==0)
                assert disconnected['setup']['waiting'] and disconnected['seconds']==0
                sockets[0]=await websockets.connect(f'ws://127.0.0.1:18113/api/companion/ws?profile={profiles[0]}&game=pocket-aces')
                assert not (await state(0))['setup']['ready']
                for socket in sockets: await socket.send(json.dumps({'action':'ready','ready':True}))
                views=[await message(socket,lambda m:m.get('type')=='state' and not m['setup']['waiting']) for socket in sockets]
                for i,v in enumerate(views):
                    assert len(v['you']['cards'])==2
                    assert all('cards' not in player for player in v['players'])
                    assert v['you']['name']==['Clover','Peaches'][i]
                assert not set(views[0]['you']['cards']) & set(views[1]['you']['cards'])
                turn=next(i for i,v in enumerate(views) if v['actions'])
                wrong=1-turn
                await sockets[wrong].send(json.dumps({'action':'fold','player_id':ids[turn],'revision':views[wrong]['revision']}))
                error=await message(sockets[wrong],lambda m:m.get('type')=='error')
                assert 'not your turn' in error['text'],error
                await sockets[turn].send(json.dumps({'action':'raise','amount':-10,'revision':views[turn]['revision']}))
                assert (await message(sockets[turn],lambda m:m.get('type')=='error'))
                # A missing phone pauses the hand instead of spending its turn clock.
                await sockets[wrong].close()
                held=await message(sockets[turn],lambda m:m.get('type')=='state' and m.get('connection_wait'))
                assert not held['actions']
                await asyncio.sleep(1.2)
                held_again=await state(turn)
                assert held_again['seconds']==held['seconds'] and held_again['revision']==held['revision']
                sockets[wrong]=await websockets.connect(f'ws://127.0.0.1:18113/api/companion/ws?profile={profiles[wrong]}&game=pocket-aces')
                await message(sockets[turn],lambda m:m.get('type')=='state' and not m.get('connection_wait'))
                # Pause stops timers and rejects phone actions without changing the hand.
                await overlay.send(json.dumps({'type':'pause'}))
                paused=await message(sockets[turn],lambda m:m.get('type')=='state' and m.get('paused'))
                await sockets[turn].send(json.dumps({'action':'fold','revision':paused['revision']}))
                assert 'paused' in (await message(sockets[turn],lambda m:m.get('type')=='error'))['text']
                await asyncio.sleep(1.1)
                await overlay.send(json.dumps({'type':'resume'}))
                resumed=await message(sockets[turn],lambda m:m.get('type')=='state' and not m.get('paused'))
                assert resumed['revision']==paused['revision'] and resumed['seconds']==paused['seconds']
                # Complete all streets using the real phone -> relay -> game path.
                snapshots=[resumed, await state(wrong)] if turn==0 else [await state(wrong),resumed]
                for _ in range(20):
                    active=next(i for i,v in enumerate(snapshots) if v['actions'])
                    v=snapshots[active]
                    await sockets[active].send(json.dumps({'action':'check' if v['actions']['check'] else 'call','revision':v['revision']}))
                    snapshots=[await message(s,lambda m:m.get('type')=='state' and m['revision']>v['revision']) for s in sockets]
                    if snapshots[0]['over']:break
                assert snapshots[0]['over'] and len(snapshots[0]['board'])==5
                assert sum(p['chips'] for p in snapshots[0]['players'])==2000
                hand=snapshots[0]['hand']
                next_view=await message(sockets[0],lambda m:m.get('type')=='state' and m['hand']>hand,25)
                assert not next_view['over']
                for s in sockets:await s.close()
                # Reconnect receives the same private hand, not a fresh deal.
                async with websockets.connect(f'ws://127.0.0.1:18113/api/companion/ws?profile={profiles[0]}&game=pocket-aces') as reconnected:
                    restored=await message(reconnected,lambda m:m.get('type')=='state')
                    assert restored['you']['cards']==next_view['you']['cards']
                fixture={'urls':urls,'ids':ids,'base':base,'daemon':'ws://127.0.0.1:18112'}
                pathlib.Path(args.fixture).write_text(json.dumps(fixture))
                print('POCKET_ACES_INTEGRATION_PASS: real host, targeted hands, spoofed sender rejection, illegal raise, pause/resume, full showdown, next hand, reconnect',flush=True)
                if args.phone_test:
                    await asyncio.to_thread(subprocess.run,['node',str(ROOT/'tests/phone.cjs'),args.fixture,args.screenshots],check=True,timeout=90)
                if args.serve:
                    print('Disposable preview is running on port 18113.',flush=True)
                    await asyncio.sleep(3600)
        finally:
            failed=sys.exc_info()[0] is not None
            # Host loss tells the SDK to exit, including a native Windows game
            # whose WSL interop process cannot directly terminate its window.
            if args.windows_game and children:
                children[0].terminate()
                try:children[0].wait(timeout=5)
                except subprocess.TimeoutExpired:children[0].kill();children[0].wait()
                await asyncio.sleep(2.5)
            for proc in reversed(children):
                proc.terminate()
                try:proc.wait(timeout=5)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            for log in logs:log.close()
            for log in folder.glob('*.log'):
                if failed or 'ERROR' in log.read_text(): print(log.name,log.read_text()[-4000:])
            pathlib.Path(args.fixture).unlink(missing_ok=True)

if __name__=='__main__':asyncio.run(main())
