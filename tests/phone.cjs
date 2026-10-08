// Test real phone pages against tests/integration.py --serve, no mocked game state.
const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
  const fixture = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const output = process.argv[3];
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? {executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE} : {});
  try {
    const pages = [], errors = [], contexts = [];
    for (const [i, url] of fixture.urls.entries()) {
      const context = await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
      contexts.push(context);
      await context.addInitScript(() => {
        const Socket = window.WebSocket;
        window.WebSocket = class extends Socket { constructor(...args) { super(...args); window.testSocket = this; } };
      });
      const page = await context.newPage(); pages.push(page);
      page.on('pageerror',e=>errors.push(e.message));
      await page.goto(url);
      await page.waitForFunction(()=>document.querySelector('#connection').textContent==='Private hand');
      await page.waitForFunction(()=>!document.querySelector('#hand-toggle').disabled);
      assert.equal(await page.locator('#hand').textContent(),'◆◆','private cards start hidden');
      assert.equal(await page.locator('#hand-toggle').getAttribute('aria-label'),'Show cards');
      assert.equal(await page.locator('#name').textContent(), ['Clover','Peaches'][i]);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    }
    await pages[0].screenshot({path:output+'/phone-hidden.png',fullPage:true});
    const revealedHands=[];
    for (const [i,page] of pages.entries()) {
      await page.locator('#hand-toggle').tap();
      revealedHands.push(await page.locator('#hand').textContent());
      assert.notEqual(revealedHands[i],'◆◆','tap reveals the hand');
      if(i===0) await page.screenshot({path:output+'/phone-revealed.png',fullPage:true});
      await page.locator('#hand-toggle').tap();
      assert.equal(await page.locator('#hand').textContent(),'◆◆','second tap hides the hand');
    }
    assert.notEqual(...revealedHands);
    await pages[0].waitForTimeout(1200);
    assert.equal(await pages[0].locator('#hand').textContent(),'◆◆','state updates do not reveal cards');
    await pages[0].locator('#hand-toggle').tap();
    await pages[0].evaluate(()=>window.dispatchEvent(new Event('blur')));
    assert.equal(await pages[0].locator('#hand').textContent(),'◆◆','leaving the page conceals the hand');
    let turn = -1;
    for (let attempt=0;attempt<120 && turn<0;attempt++) {
      for(let i=0;i<2;i++) if(await pages[i].locator('#actions').isVisible()) turn=i;
      if(turn<0) await pages[0].waitForTimeout(150);
    }
    assert.ok(turn>=0,'one phone has the turn');
    await pages[turn].screenshot({path:output+'/phone-your-turn.png',fullPage:true});
    await pages[1-turn].screenshot({path:output+'/phone-waiting.png',fullPage:true});
    const actor=pages[turn], other=pages[1-turn];
    await actor.locator('#minimum').click();
    await actor.locator('#raise').click();
    await other.locator('#actions').waitFor({state:'visible'});
    assert.match(await other.locator('#match').textContent(),/^Call \d+/);
    await other.locator('#fold').click();
    await other.waitForFunction(()=>document.querySelector('#turn').textContent==='Hand complete');
    await actor.screenshot({path:output+'/phone-result.png',fullPage:true});
    // Showing a finished hand must not expose the next hand when it is dealt.
    if (await actor.locator('#hand-toggle').getAttribute('aria-expanded')==='false') await actor.locator('#hand-toggle').tap();
    const previousHand=await actor.locator('#street').textContent();
    await actor.waitForFunction(previous=>document.querySelector('#street').textContent!==previous && document.querySelector('#street').textContent.includes('Pre-flop'),previousHand);
    assert.equal(await actor.locator('#hand').textContent(),'◆◆','new hand is hidden');
    await actor.locator('#hand-toggle').tap();
    await actor.reload();
    await actor.waitForFunction(()=>document.querySelector('#connection').textContent==='Private hand');
    assert.equal(await actor.locator('#name').textContent(),['Clover','Peaches'][turn]);
    assert.equal(await actor.locator('#hand').textContent(),'◆◆','refresh defaults to hidden');
    await actor.locator('#hand-toggle').tap();
    await actor.evaluate(()=>window.testSocket.close());
    await actor.waitForFunction(()=>document.querySelector('#connection').textContent.includes('Reconnecting'));
    await actor.waitForFunction(()=>document.querySelector('#connection').textContent==='Private hand');
    assert.equal(await actor.locator('#hand').textContent(),'◆◆','reconnect defaults to hidden');
    assert.deepEqual(errors,[]);
    console.log('POCKET_ACES_PHONE_PASS: hidden by default, tap reveal/hide, state updates, blur, new hand, refresh/reconnect, two private touch views, raise/fold, no overflow or JavaScript errors');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
