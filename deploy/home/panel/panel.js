const states = {
  identity: document.getElementById('identity'),
  api: document.getElementById('api'),
  provisioning: document.getElementById('provisioning')
};
const checked = document.getElementById('checked');
const button = document.getElementById('refresh');
const usersButton = document.getElementById('refresh-users');
const usersList = document.getElementById('users-list');
const usersMessage = document.getElementById('users-message');
function show(element, label, kind) {
  element.textContent = label;
  element.className = 'state ' + kind;
}
async function readJson(path) {
  const response = await fetch(path, {cache: 'no-store', credentials: 'same-origin'});
  if (!response.ok) throw new Error(String(response.status));
  return response.json();
}
async function refresh() {
  button.disabled = true;
  const results = await Promise.allSettled([
    readJson('/auth/realms/nona/.well-known/openid-configuration'),
    readJson('/v1/info')
  ]);
  const identity = results[0];
  const api = results[1];
  show(states.identity,
    identity.status === 'fulfilled' && identity.value.issuer === 'https://nona.server.basketref.ru/auth/realms/nona' ? 'Работает' : 'Недоступна',
    identity.status === 'fulfilled' && identity.value.issuer === 'https://nona.server.basketref.ru/auth/realms/nona' ? 'ok' : 'error');
  const apiReady = api.status === 'fulfilled' && api.value.authentication === 'keycloak';
  show(states.api, apiReady ? 'Работает' : 'Недоступен', apiReady ? 'ok' : 'error');
  show(states.provisioning,
    apiReady && api.value.provisioning_enabled === true ? 'Служба запущена' : 'Пока выключена',
    apiReady && api.value.provisioning_enabled === true ? 'ok' : 'wait');
  checked.textContent = 'Проверено: ' + new Intl.DateTimeFormat('ru-RU', {dateStyle:'medium',timeStyle:'short'}).format(new Date());
  button.disabled = false;
}
button.addEventListener('click', refresh);
refresh();

const accessLabels = {
  pending: 'Ожидает решения', approved: 'Доступ разрешён',
  revoking: 'Отзываем доступ', denied: 'Без доступа',
  deleting: 'Удаляем аккаунт'
};
const expandedUsers = new Set();
const dateFormat = new Intl.DateTimeFormat('ru-RU', {dateStyle: 'medium', timeStyle: 'short'});
function deviceRow(user, device) {
  const row = document.createElement('div');
  row.className = 'device-row';
  const identity = document.createElement('div');
  identity.className = 'device-identity';
  const name = document.createElement('strong');
  name.textContent = device.label;
  const detail = document.createElement('small');
  detail.textContent = `Добавлено ${dateFormat.format(new Date(device.created_at))} · ID ${device.id.slice(0, 8)}`;
  detail.title = device.id;
  identity.append(name, detail);
  const status = document.createElement('span');
  status.className = `device-status ${device.revoked_at ? 'revoked' : 'active'}`;
  status.textContent = device.revoked_at
    ? `Отозвано ${dateFormat.format(new Date(device.revoked_at))}`
    : 'Активно';
  row.append(identity, status);
  if (!device.revoked_at) {
    const revoke = document.createElement('button');
    revoke.type = 'button';
    revoke.className = 'danger';
    revoke.textContent = 'Отозвать доступ';
    revoke.addEventListener('click', async () => {
      if (!confirm(`Отозвать доступ устройства «${device.label}» (ID ${device.id.slice(0, 8)}) у ${user.username}? Его VPN-доступ будет удалён. При новом входе пользователь сможет зарегистрировать устройство снова.`)) return;
      revoke.disabled = true;
      revoke.textContent = 'Отзываем…';
      try {
        const response = await fetch(`/admin/api/users/${encodeURIComponent(user.id)}/devices/${encodeURIComponent(device.id)}`, {
          method: 'DELETE', credentials: 'same-origin', cache: 'no-store'
        });
        if (!response.ok) throw new Error(String(response.status));
        await loadUsers();
      } catch (_) {
        revoke.disabled = false;
        revoke.textContent = 'Отозвать доступ';
        usersMessage.textContent = 'Не удалось отозвать устройство. Проверьте связь с VPN-узлами и повторите попытку.';
      }
    });
    row.append(revoke);
  }
  return row;
}
function userRow(user, canManageOperators, canDeleteUsers) {
  const entry = document.createElement('div');
  entry.className = 'user-entry';
  const row = document.createElement('div');
  row.className = 'user-row';
  const identity = document.createElement('div');
  identity.className = 'user-identity';
  const name = document.createElement('strong');
  name.textContent = user.username;
  const detail = document.createElement('small');
  detail.textContent = `${user.active_devices} устройств · ${user.ready_devices} конфигураций`;
  if (user.retrying_devices > 0) detail.textContent += ` · повторяем выдачу: ${user.retrying_devices}`;
  if (user.operator) detail.textContent += ' · Администратор';
  identity.append(name, detail);
  const status = document.createElement('span');
  status.className = `access-status ${user.status}`;
  status.textContent = user.status === 'approved' && user.retrying_devices > 0
    ? 'Доступ разрешён · повторяем выдачу'
    : user.status === 'approved' && user.active_devices > user.ready_devices
      ? 'Доступ разрешён · настройка ожидается'
    : accessLabels[user.status] || 'Неизвестно';
  const actions = document.createElement('div');
  actions.className = 'user-actions';
  const devicesButton = document.createElement('button');
  devicesButton.type = 'button';
  devicesButton.textContent = 'Устройства';
  devicesButton.setAttribute('aria-expanded', String(expandedUsers.has(user.id)));
  devicesButton.setAttribute('aria-controls', `devices-${user.id}`);
  actions.append(devicesButton);
  const devicesPanel = document.createElement('div');
  devicesPanel.id = `devices-${user.id}`;
  devicesPanel.className = 'devices-panel';
  devicesPanel.hidden = !expandedUsers.has(user.id);
  async function loadDevices() {
    devicesPanel.textContent = 'Загружаем устройства…';
    try {
      const data = await readJson(`/admin/api/users/${encodeURIComponent(user.id)}/devices`);
      if (!Array.isArray(data.devices)) throw new Error('invalid devices');
      const devices = data.devices.slice().sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
      const heading = document.createElement('p');
      heading.className = 'devices-heading';
      const activeCount = devices.filter(device => !device.revoked_at).length;
      heading.textContent = `Всего регистраций: ${devices.length} · активных: ${activeCount}`;
      if (devices.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'devices-empty';
        empty.textContent = 'Устройств пока нет.';
        devicesPanel.replaceChildren(heading, empty);
      } else {
        const list = document.createElement('div');
        list.className = 'devices-list';
        list.replaceChildren(...devices.map(device => deviceRow(user, device)));
        devicesPanel.replaceChildren(heading, list);
      }
    } catch (_) {
      devicesPanel.textContent = 'Не удалось загрузить устройства. Закройте список и откройте снова.';
    }
  }
  devicesButton.addEventListener('click', () => {
    const expanded = !expandedUsers.has(user.id);
    if (expanded) expandedUsers.add(user.id);
    else expandedUsers.delete(user.id);
    devicesPanel.hidden = !expanded;
    devicesButton.setAttribute('aria-expanded', String(expanded));
    if (expanded) loadDevices();
  });
  if (user.status === 'pending' || user.status === 'denied') {
    const approve = document.createElement('button');
    approve.type = 'button';
    approve.textContent = 'Разрешить VPN';
    approve.addEventListener('click', () => changeAccess(user, 'approve'));
    actions.append(approve);
  }
  if (user.status === 'approved' || user.status === 'pending') {
    const deny = document.createElement('button');
    deny.type = 'button';
    deny.textContent = user.status === 'approved' ? 'Отозвать' : 'Отклонить';
    deny.addEventListener('click', () => changeAccess(user, 'deny'));
    actions.append(deny);
  }
  if (canManageOperators && !user.owner && user.status !== 'deleting') {
    const operator = document.createElement('button');
    operator.type = 'button';
    operator.textContent = user.operator ? 'Убрать администратора' : 'Назначить администратором';
    operator.addEventListener('click', () => changeOperator(user, !user.operator));
    actions.append(operator);
  }
  if (canDeleteUsers && !user.owner && user.status !== 'deleting') {
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'danger';
    remove.textContent = 'Удалить аккаунт';
    remove.addEventListener('click', () => deleteUser(user));
    actions.append(remove);
  }
  row.append(identity, status, actions);
  entry.append(row, devicesPanel);
  entry.loadDevices = loadDevices;
  entry.userId = user.id;
  return entry;
}
async function loadUsers() {
  usersButton.disabled = true;
  try {
    const data = await readJson('/admin/api/users');
    const rows = data.users.map(user => userRow(user, data.can_manage_operators, data.can_delete_users));
    usersList.replaceChildren(...rows);
    rows.filter(row => expandedUsers.has(row.userId)).forEach(row => row.loadDevices());
    usersMessage.textContent = data.users.length === 0
      ? 'Зарегистрированных пользователей пока нет.'
      : `${data.users.length} пользователей`;
  } catch (_) {
    usersMessage.textContent = 'Не удалось загрузить пользователей. Повторите попытку.';
  } finally {
    usersButton.disabled = false;
  }
}
async function changeOperator(user, enabled) {
  if (!confirm(`${enabled ? 'Дать' : 'Убрать'} доступ к панели для ${user.username}?`)) return;
  usersMessage.textContent = 'Обновляем права…';
  try {
    const response = await fetch(`/admin/api/users/${encodeURIComponent(user.id)}/operator`, {
      method: 'POST', credentials: 'same-origin', cache: 'no-store',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify({enabled})
    });
    if (!response.ok) throw new Error(String(response.status));
    await loadUsers();
  } catch (_) {
    usersMessage.textContent = 'Не удалось изменить права администратора.';
  }
}
async function changeAccess(user, decision) {
  if (decision === 'deny' && user.status === 'approved' &&
      !confirm(`Отозвать VPN-доступ у ${user.username}? Сервер удалит данные доступа для его устройств.`)) return;
  usersMessage.textContent = 'Сохраняем решение…';
  try {
    const response = await fetch(`/admin/api/users/${encodeURIComponent(user.id)}/access`, {
      method: 'POST', credentials: 'same-origin', cache: 'no-store',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify({decision})
    });
    if (!response.ok) throw new Error(String(response.status));
    await loadUsers();
  } catch (_) {
    usersMessage.textContent = 'Не удалось сохранить решение. Повторите попытку.';
  }
}
async function deleteUser(user) {
  const typed = prompt(`Удалить аккаунт «${user.username}» вместе с доступом к панели и VPN? Это действие нельзя отменить. Для подтверждения введите имя пользователя:`);
  if (typed !== user.username) return;
  usersMessage.textContent = 'Удаляем аккаунт и данные доступа…';
  try {
    const response = await fetch(`/admin/api/users/${encodeURIComponent(user.id)}`, {
      method: 'DELETE', credentials: 'same-origin', cache: 'no-store'
    });
    if (!response.ok) throw new Error(String(response.status));
    await loadUsers();
  } catch (_) {
    usersMessage.textContent = 'Не удалось удалить аккаунт. Повторите попытку.';
  }
}
usersButton.addEventListener('click', loadUsers);
loadUsers();
