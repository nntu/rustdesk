import { T } from '@/utils/i18n';

export function timeAgo(time) {
  const now = new Date().getTime();
  const after = new Date(time).getTime();
  const dis = now - after;
  if (dis < 60 * 1000) {
    return T('JustNow');
  }
  if (dis < 60 * 60 * 1000) {
    const num = Math.floor(dis / (60 * 1000));
    return T('MinutesAgo', { param: num }, num);
  }
  if (dis < 24 * 60 * 60 * 1000) {
    const num = Math.floor(dis / (60 * 60 * 1000));
    return T('HoursAgo', { param: num }, num);
  }
  if (dis < 30 * 24 * 60 * 60 * 1000) {
    const num = Math.floor(dis / (24 * 60 * 60 * 1000));
    return T('DaysAgo', { param: num }, num);
  }
  if (dis < 12 * 30 * 24 * 60 * 60 * 1000) {
    const num = Math.floor(dis / (30 * 24 * 60 * 60 * 1000));
    return T('MonthsAgo', { param: num }, num);
  }
  const num = Math.floor(dis / (12 * 30 * 24 * 60 * 60 * 1000));
  return T('YearsAgo', { param: num }, num);
}

export function formatTime(unix, format = 'yyyy-MM-dd hh:mm:ss') {
  const date = new Date(unix);
  const o = {
    'M+': date.getMonth() + 1,
    'd+': date.getDate(),
    'h+': date.getHours(),
    'm+': date.getMinutes(),
    's+': date.getSeconds(),
    'q+': Math.floor((date.getMonth() + 3) / 3),
    S: date.getMilliseconds(),
  };
  if (/(y+)/.test(format)) {
    format = format.replace(RegExp.$1, (date.getFullYear() + '').substr(4 - RegExp.$1.length));
  }
  for (const k in o) {
    if (new RegExp('(' + k + ')').test(format)) {
      format = format.replace(
        RegExp.$1,
        RegExp.$1.length === 1 ? o[k] : ('00' + o[k]).substr(('' + o[k]).length),
      );
    }
  }
  return format;
}
