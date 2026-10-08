/* Only this player's projected view arrives here. Never infer legal actions. */
(() => {
  const $ = id => document.getElementById(id);
  let state = null, pending = false, online = false, previousRevision = -1;
  const faces = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
  const suits = ['♣','♦','♥','♠'];
  function cards(target, values, backs = 0) {
    target.replaceChildren();
    for (let i = 0; i < Math.max(values.length, backs); i++) {
      const c = values[i], el = document.createElement('div');
      const suit = Number.isInteger(c) ? Math.floor(c / 13) : -1;
      el.className = `card ${suit < 0 ? 'back' : [1,2].includes(suit) ? 'red' : ''}`;
      el.textContent = suit < 0 ? '◆' : faces[c % 13] + suits[suit];
      target.append(el);
    }
  }
  function amount(value) {
    if (!state?.actions?.raise) return;
    $('amount').value = Math.max(state.actions.min, Math.min(state.actions.max, Math.round(value)));
    $('amount-label').textContent = $('amount').value;
    $('raise').textContent = `Raise to ${$('amount').value}`;
  }
  function availability() {
    for (const b of document.querySelectorAll('button')) b.disabled = pending || !online;
  }
  function receive(data) {
    if (data.type === 'error') { $('notice').textContent = data.text; pending = false; availability(); return; }
    if (data.type !== 'state' || !data.you) return;
    const changed = data.revision !== previousRevision;
    state = data;
    if (changed) { pending = false; $('notice').textContent = ''; }
    previousRevision = data.revision;
    $('name').textContent = data.you.name;
    $('chips').textContent = `${data.you.chips.toLocaleString()} chips`;
    cards($('hand'), data.you.cards);
    cards($('board'), data.board, 5);
    $('street').textContent = `Hand ${data.hand} · ${data.street}`;
    $('pot').textContent = `POT ${data.pot.toLocaleString()}`;
    const ownTurn = Object.keys(data.actions).length > 0;
    $('turn').textContent = data.paused ? 'Table paused' : data.over ? 'Hand complete' : ownTurn ? `Your move · ${data.seconds}s` : `${data.turn}'s turn`;
    $('result').textContent = data.over ? `${data.result}. Next hand shortly.` : data.you.folded ? 'Folded. You’re in again next hand.' : '';
    $('actions').hidden = !ownTurn || data.paused;
    $('match').textContent = data.actions.check ? 'Check' : `Call ${data.actions.call || 0}`;
    $('raising').hidden = !data.actions.raise;
    if (data.actions.raise) {
      $('amount').min = data.actions.min;
      $('amount').max = data.actions.max;
      amount(changed ? data.actions.min : Number($('amount').value));
    }
    availability();
  }
  const game = GameNight.connect(receive, status => {
    online = status === 'connected';
    pending = false;
    $('connection').textContent = online ? 'Private hand' : 'Reconnecting…';
    availability();
    if (online) game.send({action:'sync'});
  });
  function act(action, amountValue) {
    if (!online || pending || !state) return;
    pending = true;
    availability();
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
