/* Only this player's projected view arrives here. Never infer legal actions. */
(() => {
  const $ = id => document.getElementById(id);
  let state = null, pending = false, online = false, synced = false, previousRevision = -1;
  let revealed = false, wasTurn = false;
  const faces = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
  const suits = ['♣','♦','♥','♠'];
  const waiting = () => state?.setup?.waiting === true;
  const playable = () => online && synced && !!state && !waiting();
  function cards(target, values = [], backs = 0) {
    target.replaceChildren();
    for (let i = 0; i < Math.max(values.length, backs); i++) {
      const c = values[i], el = document.createElement('span');
      const suit = Number.isInteger(c) && c >= 0 && c < 52 ? Math.floor(c / 13) : -1;
      el.className = `card ${suit < 0 ? 'back' : [1,2].includes(suit) ? 'red' : ''}`;
      el.textContent = suit < 0 ? '◆' : faces[c % 13] + suits[suit];
      target.append(el);
    }
  }
  function renderHand() {
    const values = revealed && playable() ? state?.you?.cards || [] : [];
    cards($('hand'), values, 2);
    $('hand-hint').textContent = revealed ? 'Tap to hide cards' : 'Tap to show cards';
    $('hand-toggle').setAttribute('aria-expanded', String(revealed));
    $('hand-toggle').setAttribute('aria-label', revealed
      ? `Hide cards: ${values.map(c => faces[c % 13] + suits[Math.floor(c / 13)]).join(', ')}` : 'Show cards');
  }
  function hideHand() { revealed = false; renderHand(); }
  function amount(value) {
    if (!state?.actions?.raise) return;
    $('amount').value = Math.max(state.actions.min, Math.min(state.actions.max, Math.round(value)));
    $('amount-label').textContent = $('amount').value;
    $('raise').textContent = `Raise to ${$('amount').value}`;
  }
  function availability() {
    const live = playable(), stopped = state?.paused;
    for (const b of document.querySelectorAll('#actions button, #actions input')) b.disabled = pending || !live || stopped;
    $('hand-toggle').disabled = !live || stopped || !state?.you?.cards?.length;
    $('ready').disabled = pending || !online || !synced || !waiting();
    $('gameplay').hidden = !live;
    $('setup').hidden = !waiting() || !synced;
    $('reconnecting').hidden = online && synced;
    $('actions').hidden = !live || stopped || !Object.keys(state?.actions || {}).length;
    // Off turn the phone is calm and almost empty, so nobody keeps watching it.
    // On turn it lights up. Setup and reconnecting keep the saloon style.
    const myTurn = live && !stopped && Object.keys(state?.actions || {}).length > 0;
    document.body.classList.toggle('my-turn', myTurn);
    document.body.classList.toggle('idle', live && !myTurn);
    if (myTurn && !wasTurn) navigator.vibrate?.([60, 40, 60]);
    wasTurn = myTurn;
  }
  function renderSetup(data) {
    const setup = data.setup;
    if (!setup?.waiting) return;
    $('ready-count').textContent = `${setup.count} / ${setup.total} ready`;
    $('players').replaceChildren();
    for (const player of setup.players) {
      const row = document.createElement('li'), avatar = document.createElement('span');
      const name = document.createElement('span'), status = document.createElement('span');
      const own = player.id === data.you.id;
      row.className = player.bot || player.ready ? 'player is-ready' : 'player';
      avatar.className = 'avatar';
      avatar.textContent = player.name.slice(0, 1).toUpperCase();
      // Server colors are optional; CSS rejects values that are not colors.
      if (typeof player.color === 'string') avatar.style.backgroundColor = player.color;
      name.className = 'player-name'; name.textContent = player.name + (own ? ' · You' : '');
      status.className = 'player-status';
      status.textContent = player.bot ? 'House bot' : !player.connected ? 'Connecting…' : player.ready ? '✓ Ready' : 'Not ready';
      row.append(avatar, name, status); $('players').append(row);
    }
    $('ready').textContent = setup.ready ? '✓ Ready · tap to undo' : "I'm ready →";
    $('ready').classList.toggle('is-ready', setup.ready);
    $('ready-hint').textContent = setup.ready ? 'You’re ready. Waiting for the rest of the table.' : 'Your cards stay private on this phone.';
  }
  function receive(data) {
    if (data.type === 'error') { $('notice').textContent = data.text; pending = false; availability(); return; }
    if (data.type !== 'state' || !data.you || !online) return;
    const changed = data.revision !== previousRevision;
    if (data.hand !== state?.hand || JSON.stringify(data.you.cards) !== JSON.stringify(state?.you?.cards) || data.paused || data.setup?.waiting) revealed = false;
    state = data; synced = true;
    if (changed || waiting()) { pending = false; $('notice').textContent = ''; }
    previousRevision = data.revision;
    $('name').textContent = data.you.name;
    $('chips').textContent = `${data.you.chips.toLocaleString()} chips`;
    $('connection').textContent = waiting() ? 'Connected' : 'Private hand';
    renderSetup(data);
    renderHand();
    cards($('board'), waiting() ? [] : data.board, waiting() ? 0 : 5);
    $('street').textContent = `Hand ${data.hand} · ${data.street}`;
    $('pot').textContent = `POT ${data.pot.toLocaleString()}`;
    const ownTurn = Object.keys(data.actions).length > 0;
    $('turn').textContent = data.paused ? 'Table paused' : data.over ? 'Hand complete' : ownTurn ? 'Your move' : `${data.turn}'s turn`;
    $('seconds').textContent = ownTurn && !data.paused ? `${data.seconds}s` : '';
    $('result').textContent = data.over ? `${data.result}. Next hand shortly.` : '';
    $('idle-chips').textContent = data.paused ? 'Table paused' : data.you.folded ? 'Folded' : `${data.you.chips.toLocaleString()} chips`;
    $('match').textContent = data.actions.check ? 'Check' : `Call ${data.actions.call || 0}`;
    $('raising').hidden = !data.actions.raise;
    if (data.actions.raise) {
      $('amount').min = data.actions.min; $('amount').max = data.actions.max;
      amount(changed ? data.actions.min : Number($('amount').value));
    }
    availability();
  }
  const game = GameNight.connect(receive, status => {
    online = status === 'connected'; synced = false; pending = false;
    hideHand();
    $('connection').textContent = online ? 'Connecting…' : 'Reconnecting…';
    $('reconnecting').querySelector('h2').textContent = online ? 'Taking your seat' : 'Reconnecting to the table';
    $('reconnecting').querySelector('p').textContent = online ? 'Your private seat will appear here.' : 'Your cards are hidden. Keep this page open.';
    availability();
    if (online) queueMicrotask(() => game.send({action:'sync'}));
  });
  $('ready').onclick = () => {
    if (!online || !synced || pending || !waiting()) return;
    pending = true; availability();
    game.send({action:'ready', ready:!state.setup.ready});
  };
  $('hand-toggle').onclick = () => { if ($('hand-toggle').disabled) return; revealed = !revealed; renderHand(); };
  document.addEventListener('visibilitychange', () => { if (document.hidden) hideHand(); });
  window.addEventListener('blur', hideHand);
  window.addEventListener('pagehide', hideHand);
  function act(action, amountValue) {
    if (!playable() || pending || state.paused || !Object.keys(state.actions).length) return;
    pending = true; availability();
    game.send({action, amount:amountValue, revision:state.revision});
  }
  $('fold').onclick = () => act('fold');
  $('match').onclick = () => act(state.actions.check ? 'check' : 'call');
  $('raise').onclick = () => act('raise', Number($('amount').value));
  $('amount').oninput = () => amount(Number($('amount').value));
  $('minimum').onclick = () => amount(state.actions.min);
  $('half').onclick = () => amount(state.actions.min + Math.floor(state.pot / 2));
  $('pot-raise').onclick = () => amount(state.actions.min + state.pot);
  $('allin').onclick = () => amount(state.actions.max);
})();
