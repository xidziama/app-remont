import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import admin from 'firebase-admin';
import helmet from 'helmet';
import morgan from 'morgan';

// Минимальный backend нужен как точка расширения для production-логики:
// webhooks, платежи, административные операции, интеграции с внешними API.
// На этапе MVP приложение работает напрямую с Firebase, поэтому backend
// содержит только healthcheck и пример проверки Firebase ID token.
const app = express();
const port = process.env.PORT || 8080;
const projectId = process.env.FIREBASE_PROJECT_ID || 'remont-local';

// Firebase Admin SDK подключается к эмуляторам через переменные окружения
// из docker-compose.yml: FIRESTORE_EMULATOR_HOST и FIREBASE_AUTH_EMULATOR_HOST.
if (!admin.apps.length) {
  admin.initializeApp({
    projectId,
    storageBucket: `${projectId}.appspot.com`,
  });
}

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Простой endpoint для проверки, что контейнер backend поднялся.
app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'remont-backend',
    projectId,
  });
});

// Пример защищенного endpoint. Клиент передает Firebase ID token в заголовке:
// Authorization: Bearer <token>. Backend проверяет токен через Admin SDK.
app.get('/api/me', async (req, res) => {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  // Если токена нет, backend не знает, кто делает запрос.
  if (!token) {
    return res.status(401).json({ error: 'Missing bearer token' });
  }

  try {
    // verifyIdToken работает и с Firebase Auth emulator, и с production Firebase.
    const decoded = await admin.auth().verifyIdToken(token);
    return res.json({ uid: decoded.uid, phoneNumber: decoded.phone_number ?? null });
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
});

app.listen(port, () => {
  console.log(`Backend listening on ${port}`);
});
