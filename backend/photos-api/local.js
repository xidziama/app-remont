'use strict';

// Локальный HTTP-сервер для ручной проверки перед сборкой в ZIP. Оборачивает
// index.handler в обычный Node http-сервер, повторяя форму события API
// Gateway (httpMethod/path/headers/body), чтобы код был идентичен тому, что
// выполнится в облаке.
//
// Запуск против Firebase Emulator Suite (docker-compose уже поднимает auth+
// firestore): задайте FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 и
// FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099, тогда FIREBASE_SA_JSON не
// нужен. S3_ACCESS_KEY/S3_SECRET_KEY нужны настоящие (или тестовые), чтобы
// подписи реально проверялись против Yandex.

const http = require('http');
const { handler } = require('./index');

const port = Number(process.env.LOCAL_PORT) || 8082;

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', async () => {
    const event = {
      httpMethod: req.method,
      path: req.url,
      headers: req.headers,
      body: Buffer.concat(chunks).toString('utf8'),
      isBase64Encoded: false,
    };

    try {
      const result = await handler(event, {});
      res.writeHead(result.statusCode, result.headers);
      res.end(result.body);
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'internal', message: String(err && err.message) }));
    }
  });
});

server.listen(port, () => {
  console.log(`photos-api: локальный сервер слушает http://localhost:${port}`);
  console.log('Маршруты: POST /put-url, POST /get-urls, POST /delete');
});
