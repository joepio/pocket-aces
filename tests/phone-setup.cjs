// Deterministic phone setup and privacy checks, without a running GameNight host.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
(async () => {
  const output = process.argv[2] || '/tmp/pocket-aces-phone';
  fs.mkdirSync(output,{recursive:true});
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? {executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE} : {});
  const errors=[];
  const players=[{id:1,name:'Clover',color:'#517750',bot:false,connected:true,ready:false},{id:2,name:'Peaches',color:'#bc7754',bot:false,connected:false,ready:false},{id:3,name:'The Dealer',color:'#8e7443',bot:true,connected:true,ready:true}];
  const initial={type:'state',revision:1,hand:0,street:'Waiting',pot:0,board:[],seconds:0,turn:'',actions:{},paused:false,over:false,connection_wait:false,you:{id:1,name:'Clover',chips:1000,cards:[],folded:false},setup:{waiting:true,ready:false,count:0,total:2,players}};
  try {
    const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
    await context.route('http://phone.test/**',route=>{
      const name=new URL(route.request().url()).pathname;
      if(name==='/assets/companion.js') return route.fulfill({contentType:'application/javascript',body:`window.sent=[]; window.GameNight={connect(receive,status){window.receive=receive;window.connectionStatus=status;queueMicrotask(()=>status('connected'));return {send(message){window.sent.push(message)}}}};`});
      const file=path.join(__dirname,'../phone',name==='/'?'index.html':path.basename(name));
      return route.fulfill({contentType:name.endsWith('.css')?'text/css':name.endsWith('.js')?'application/javascript':'text/html',body:fs.readFileSync(file)});
    });
    const page=await context.newPage(); page.on('pageerror',e=>errors.push(e.message));
    await page.goto('http://phone.test/');
    const receive=state=>page.evaluate(state=>window.receive(state),state);
    await receive(initial);
    assert.equal(await page.locator('#setup').isVisible(),true);
    assert.equal(await page.locator('#gameplay').isVisible(),false);
    assert.equal(await page.locator('#actions').isVisible(),false);
    assert.equal(await page.locator('#hand').textContent(),'◆◆');
    assert.equal(await page.locator('#name').textContent(),'Clover');
    assert.deepEqual(await page.locator('.player-name').allTextContents(),['Clover · You','Peaches','The Dealer']);
    assert.deepEqual(await page.locator('.player-status').allTextContents(),['Not ready','Connecting…','House bot']);
    await page.screenshot({path:output+'/phone-setup.png',fullPage:true});
    await page.locator('#ready').tap();
    assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'ready',ready:true});
    assert.equal(await page.locator('#ready').isDisabled(),true);
    const ready=structuredClone(initial); ready.revision++; ready.setup.ready=true;ready.setup.count=1;ready.setup.players[0].ready=true;
    await receive(ready);
    assert.match(await page.locator('#ready').textContent(),/Ready · tap to undo/);
    await page.screenshot({path:output+'/phone-ready.png',fullPage:true});
    await page.locator('#ready').tap();
    assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'ready',ready:false});
    await receive({...initial,revision:3});
    await page.evaluate(()=>window.connectionStatus('disconnected'));
    assert.equal(await page.locator('#ready').isDisabled(),true);
    assert.equal(await page.locator('#reconnecting').isVisible(),true);
    await page.evaluate(()=>window.connectionStatus('connected'));
    await receive({...initial,revision:4});
    assert.match(await page.locator('#ready').textContent(),/I'm ready/);
    assert.equal(await page.evaluate(()=>window.sent.filter(m=>m.action==='ready').length),2,'reconnect never automatically sends ready');
    const playing={...structuredClone(initial),revision:5,hand:1,street:'Pre-flop',pot:30,turn:'Clover',seconds:30,actions:{check:true,raise:true,min:20,max:1000},you:{...initial.you,cards:[12,51]},setup:{...initial.setup,waiting:false,ready:true,count:2}};
    await receive(playing);
    assert.equal(await page.locator('#setup').isVisible(),false);
    assert.equal(await page.locator('#actions').isVisible(),true);
    assert.equal(await page.locator('#hand').textContent(),'◆◆');
    await page.screenshot({path:output+'/phone-playing.png',fullPage:true});
    await page.locator('#hand-toggle').tap();
    assert.equal(await page.locator('#hand').textContent(),'A♣A♠');
    await page.evaluate(()=>window.connectionStatus('disconnected'));
    assert.equal(await page.locator('#hand').textContent(),'◆◆');
    assert.equal(await page.locator('#hand-toggle').isDisabled(),true);
    assert.equal(await page.locator('#gameplay').isVisible(),false);
    await page.evaluate(()=>window.connectionStatus('connected'));
    assert.equal(await page.locator('#gameplay').isVisible(),false,'stale state stays hidden until sync');
    await receive({...playing,revision:6,connection_wait:true,actions:{}});
    assert.equal(await page.locator('#actions').isVisible(),false);
    assert.equal(await page.locator('#hand-toggle').isDisabled(),true);
    assert.equal(await page.locator('#turn').textContent(),'Waiting for a phone…');
    await receive({...playing,revision:7});
    assert.equal(await page.locator('#hand').textContent(),'◆◆');
    await page.locator('#hand-toggle').tap();
    await page.evaluate(()=>window.dispatchEvent(new Event('blur')));
    assert.equal(await page.locator('#hand').textContent(),'◆◆');
    await page.locator('#hand-toggle').tap();
    await receive({...playing,revision:8,hand:2});
    assert.equal(await page.locator('#hand').textContent(),'◆◆');
    await page.locator('#raise').tap();
    assert.deepEqual(await page.evaluate(()=>window.sent.at(-1)),{action:'raise',amount:20,revision:8});
    for(const width of [320,390,540]){
      await page.setViewportSize({width,height:width===320?568:844});
      for(const state of [initial,playing]){
        await receive(state);
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`no overflow at ${width}`);
      }
    }
    await page.setViewportSize({width:320,height:568});
    await receive(initial);
    await page.screenshot({path:output+'/phone-setup-small.png',fullPage:true});
    assert.deepEqual(errors,[]);
    console.log('POCKET_ACES_PHONE_SETUP_PASS: readiness and undo, roster, no pre-deal controls, reconnect requires ready, private cards concealed, mid-hand connection pause, raise action, 320/390/540 layouts');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1});
