const states = {
  identity: document.getElementById('identity'),
  api: document.getElementById('api'),
  provisioning: document.getElementById('provisioning')
};
const checked = document.getElementById('checked');
const button = document.getElementById('refresh');
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
    apiReady && api.value.provisioning_enabled === true ? 'Включена' : 'Пока выключена',
    apiReady && api.value.provisioning_enabled === true ? 'ok' : 'wait');
  checked.textContent = 'Проверено: ' + new Intl.DateTimeFormat('ru-RU', {dateStyle:'medium',timeStyle:'short'}).format(new Date());
  button.disabled = false;
}
button.addEventListener('click', refresh);
refresh();
