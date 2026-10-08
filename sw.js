self.addEventListener('install',e=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{let d={};try{d=e.data.json();}catch(_){}
  e.waitUntil(self.registration.showNotification(d.title||'Os Doze',{body:d.body||'',icon:'icon-192.png',badge:'icon-192.png',data:{url:d.url||'/'}}));});
self.addEventListener('notificationclick',e=>{e.notification.close();
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(l=>{for(const c of l){if('focus'in c)return c.focus();}return clients.openWindow('/');}));});
