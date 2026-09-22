'use strict';

// Локальный запуск зонда с вашего компьютера (для предварительной проверки ключей).
// Секреты берутся из переменных окружения текущей сессии терминала.
// ВНИМАНИЕ: сетевые результаты с вашего ПК НЕ доказывают доступность из Yandex Cloud —
// это только проверка правильности ключей и ролей.

const { handler } = require(process.env.PROBE_ENTRY || './index.js');

handler({}, {})
  .then((report) => {
    console.log(JSON.stringify(report, null, 2));
    process.exit(0);
  })
  .catch((err) => {
    console.error('Ошибка запуска:', err && err.message);
    process.exit(1);
  });
