import { createApp } from 'vue';
import 'element-plus/dist/index.css';
import { router } from '@/router';
import ElementPlus from 'element-plus';
import en from 'element-plus/es/locale/lang/en';
import App from './App.vue';
import 'normalize.css/normalize.css';
import { pinia } from '@/store';
import '@/permission';
import '@/styles/tailwind.css';
import '@/styles/style.scss';
import * as ElementIcons from '@element-plus/icons-vue';

const app = createApp(App);
app.use(ElementPlus, { locale: en });
app.use(pinia);
app.use(router);
for (const icon in ElementIcons) {
  app.component('ElIcon' + icon, ElementIcons[icon]);
}
app.mount('#app');
