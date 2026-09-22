'use strict';

/*
 * ВРЕМЕННАЯ функция-зонд для Yandex Cloud Functions (Node.js, entry point: index.handler).
 *
 * Цель: до написания основного backend убедиться, что из Yandex Cloud доступны
 *   1) Google (публичные ключи Firebase Auth для verifyIdToken),
 *   2) Firestore проекта remont-76b60 (под сервисным аккаунтом Datastore Viewer),
 *   3) Yandex Object Storage (подпись ключом photos-signer принимается).
 *
 * Секреты берутся ТОЛЬКО из переменных окружения (S3_ACCESS_KEY, S3_SECRET_KEY,
 * FIREBASE_SA_JSON). В отчёт и в логи значения секретов не попадают: все строки
 * проходят через sanitize(). После проверки функцию нужно удалить.
 */

const https = require('https');
const crypto = require('crypto');
const aws4 = require('aws4');
const { initializeApp, getApps, getApp, cert, deleteApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

const GOOGLE_KEYS_HOST = 'www.googleapis.com';
const GOOGLE_KEYS_PATH = '/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

const NET_ERROR_CODES = new Set([
  'ENOTFOUND', 'ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT', 'EAI_AGAIN',
  'EHOSTUNREACH', 'ENETUNREACH', 'EPIPE', 'PROBE_TIMEOUT',
  'UND_ERR_CONNECT_TIMEOUT',
]);
const NET_ERROR_RE =
  /(ETIMEDOUT|ENOTFOUND|ECONNREFUSED|ECONNRESET|EAI_AGAIN|EHOSTUNREACH|ENETUNREACH|socket hang up|getaddrinfo|No connection established|DEADLINE_EXCEEDED|UNAVAILABLE|reason: connect|network-error|нет ответа за)/i;

// ---------------------------------------------------------------------------
// Конфигурация и защита от утечки секретов
// ---------------------------------------------------------------------------

function readConfig() {
  const env = (name, fallback = '') => process.env[name] ?? fallback;
  return {
    projectId: env('FIREBASE_PROJECT_ID', 'remont-76b60').trim(),
    bucket: env('S3_BUCKET', 'app-remont-photos').trim(),
    endpoint: env('S3_ENDPOINT', 'storage.yandexcloud.net')
      .trim()
      .replace(/^https?:\/\//i, '')
      .replace(/\/+$/, ''),
    region: env('S3_REGION', 'ru-central1').trim(),
    timeoutMs: Number(env('PROBE_TIMEOUT_MS')) || 12000,
    rawKeyId: env('S3_ACCESS_KEY'),
    rawSecret: env('S3_SECRET_KEY'),
    rawSaJson: env('FIREBASE_SA_JSON'),
  };
}

function loadServiceAccount(cfg) {
  const raw = cfg.rawSaJson;
  if (!raw.trim()) {
    return { ok: false, error: 'Переменная FIREBASE_SA_JSON не задана или пуста.' };
  }

  let json;
  try {
    json = JSON.parse(raw);
  } catch (_) {
    return {
      ok: false,
      error: 'FIREBASE_SA_JSON не является корректным JSON (вставьте файл ключа целиком, от { до }).',
    };
  }

  const missing = ['project_id', 'client_email', 'private_key'].filter((k) => !json[k]);
  if (missing.length > 0) {
    return { ok: false, error: `В JSON-ключе нет полей: ${missing.join(', ')}.` };
  }

  return {
    ok: true,
    json,
    info: {
      clientEmail: json.client_email,
      projectIdInKey: json.project_id,
      projectIdMatchesExpected: json.project_id === cfg.projectId,
    },
  };
}

function makeSanitizer(cfg, sa) {
  const secrets = [
    cfg.rawKeyId.trim(),
    cfg.rawSecret.trim(),
    cfg.rawSaJson.trim(),
    sa && sa.json && sa.json.private_key,
    sa && sa.json && sa.json.private_key_id,
  ]
    .filter((v) => typeof v === 'string' && v.length >= 6)
    .sort((a, b) => b.length - a.length);

  return (value) => {
    let s = String(value === undefined || value === null ? '' : value);
    for (const secret of secrets) {
      s = s.split(secret).join('***');
    }
    s = s
      .replace(/-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----/g, '***')
      .replace(/X-Amz-(Signature|Credential|Security-Token)=[^&\s"']+/gi, 'X-Amz-$1=***')
      .replace(/(Bearer|Authorization:?)\s+\S+/gi, '$1 ***')
      .replace(/\s+/g, ' ')
      .trim();
    return s.length > 300 ? `${s.slice(0, 300)}…` : s;
  };
}

function describeSecret(value) {
  if (!value) return { set: false };
  return {
    set: true,
    length: value.length,
    hasSurroundingWhitespace: value !== value.trim(),
  };
}

// ---------------------------------------------------------------------------
// Утилиты
// ---------------------------------------------------------------------------

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error(`${label}: нет ответа за ${ms} мс`);
      err.code = 'PROBE_TIMEOUT';
      reject(err);
    }, ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function describeError(err) {
  if (!err) return 'неизвестная ошибка';
  const parts = [];
  if (err.code !== undefined) parts.push(`[${err.code}]`);
  parts.push(err.message || String(err));
  return parts.join(' ');
}

function isNetworkError(err) {
  if (!err) return false;
  if (NET_ERROR_CODES.has(err.code) || err.code === 14 || err.code === 4) return true;
  return NET_ERROR_RE.test(String(err.message || err));
}

function httpsRequest({ method, host, path, headers, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const req = https.request({ method, host, path, headers, timeout: timeoutMs }, (res) => {
      const chunks = [];
      let size = 0;
      res.on('data', (chunk) => {
        size += chunk.length;
        if (size <= 65536) chunks.push(chunk);
      });
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          headers: res.headers,
          body: Buffer.concat(chunks).toString('utf8'),
        });
      });
      res.on('error', reject);
    });
    req.on('timeout', () => {
      const err = new Error(`нет ответа от ${host} за ${timeoutMs} мс`);
      err.code = 'PROBE_TIMEOUT';
      req.destroy(err);
    });
    req.on('error', reject);
    req.end();
  });
}

function getOrCreateApp(name, options) {
  const existing = getApps().find((a) => a.name === name);
  return existing ? getApp(name) : initializeApp(options, name);
}

// ---------------------------------------------------------------------------
// Проверка 1: Google public keys + firebase-admin verifyIdToken
// ---------------------------------------------------------------------------

function buildFakeIdToken(projectId) {
  // Структурно валидный JWT с неверной подписью и несуществующим kid: SDK пройдёт
  // проверку содержимого, пойдёт за публичными ключами Google (это и есть сетевой
  // запрос, который нам нужно проверить) и отклонит токен. Секретов тут нет.
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return [
    b64({ alg: 'RS256', kid: 'probe-nonexistent-kid', typ: 'JWT' }),
    b64({
      aud: projectId,
      iss: `https://securetoken.google.com/${projectId}`,
      sub: 'probe-user',
      iat: now - 60,
      auth_time: now - 60,
      exp: now + 3600,
    }),
    Buffer.from('not-a-real-signature').toString('base64url'),
  ].join('.');
}

async function checkVerifyIdToken(cfg, sanitize) {
  const started = Date.now();
  const details = {};

  const keysStarted = Date.now();
  try {
    const res = await httpsRequest({
      method: 'GET',
      host: GOOGLE_KEYS_HOST,
      path: GOOGLE_KEYS_PATH,
      timeoutMs: cfg.timeoutMs,
    });
    let keyCount = null;
    try {
      keyCount = Object.keys(JSON.parse(res.body)).length;
    } catch (_) {
      keyCount = null;
    }
    details.googlePublicKeys = {
      ok: res.status === 200 && keyCount > 0,
      httpStatus: res.status,
      keyCount,
      ms: Date.now() - keysStarted,
    };
  } catch (err) {
    details.googlePublicKeys = {
      ok: false,
      networkFailure: isNetworkError(err),
      error: sanitize(describeError(err)),
      ms: Date.now() - keysStarted,
    };
  }

  const sdkStarted = Date.now();
  try {
    const app = getOrCreateApp('probe-auth', { projectId: cfg.projectId });
    await withTimeout(
      getAuth(app).verifyIdToken(buildFakeIdToken(cfg.projectId)),
      cfg.timeoutMs,
      'verifyIdToken',
    );
    details.sdkVerifyIdToken = {
      ok: false,
      note: 'Неожиданно: поддельный токен принят. Сообщите об этом.',
      ms: Date.now() - sdkStarted,
    };
  } catch (err) {
    const message = describeError(err);
    const network =
      isNetworkError(err) ||
      /Error fetching public keys/i.test(message) ||
      err.code === 'auth/internal-error';
    const reached =
      !network && /(kid|public key|signature|Decoding Firebase ID token failed|invalid)/i.test(message);
    details.sdkVerifyIdToken = {
      ok: reached,
      reachedGoogle: network ? false : reached ? true : 'unknown',
      meaning: network
        ? 'сеть/Google недоступны'
        : reached
          ? 'токен отклонён как невалидный — это УСПЕХ связи'
          : 'неклассифицированная ошибка',
      errorCode: err.code === undefined ? null : err.code,
      message: sanitize(message),
      ms: Date.now() - sdkStarted,
    };
  }

  const keysOk = details.googlePublicKeys.ok === true;
  const sdkOk = details.sdkVerifyIdToken.ok === true;

  let status;
  let hint = null;
  if (keysOk && sdkOk) {
    status = 'OK';
  } else if (!keysOk && !sdkOk) {
    status = 'FAIL';
    hint =
      'Функция не может связаться с googleapis.com. Без этого verifyIdToken в backend работать не сможет. ' +
      'Пришлите этот отчёт — придётся менять схему (например, кэшировать публичные ключи Google другим путём).';
  } else {
    status = 'WARN';
    hint =
      'Один из двух под-тестов не прошёл, хотя второй прошёл. Пришлите отчёт целиком — разберёмся.';
  }

  return {
    status,
    ms: Date.now() - started,
    summary: keysOk
      ? 'Публичные ключи Google загружаются'
      : 'Публичные ключи Google НЕ загрузились',
    details,
    hint,
  };
}

// ---------------------------------------------------------------------------
// Проверка 2: Firestore под сервисным аккаунтом (gRPC, при неудаче — REST)
// ---------------------------------------------------------------------------

function classifyFirestoreError(err, sanitize) {
  const message = describeError(err);
  const code = err && err.code;
  const base = {
    errorCode: code === undefined ? null : code,
    message: sanitize(message),
  };

  if (isNetworkError(err)) {
    return { ...base, reached: false, outcome: 'network_unreachable' };
  }
  if (/invalid_grant|Invalid JWT|invalid_client|unauthorized_client/i.test(message)) {
    return { ...base, reached: true, outcome: 'bad_credentials' };
  }
  if (code === 16) return { ...base, reached: true, outcome: 'unauthenticated' };
  if (code === 7) return { ...base, reached: true, outcome: 'permission_denied' };
  if (code === 5) return { ...base, reached: true, outcome: 'database_not_found' };
  if (/PEM|private key|Could not load the default credentials|Failed to parse/i.test(message)) {
    return { ...base, reached: null, outcome: 'bad_key_file' };
  }
  return { ...base, reached: null, outcome: 'unclassified' };
}

async function firestoreAttempt(cfg, sa, sanitize, preferRest) {
  const mode = preferRest ? 'rest' : 'grpc';
  const name = `probe-fs-${mode}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  const started = Date.now();
  let app;
  try {
    app = initializeApp({ credential: cert(sa.json), projectId: cfg.projectId }, name);
    const db = getFirestore(app);
    if (preferRest) db.settings({ preferRest: true });
    const snap = await withTimeout(
      db.collection('probe_connectivity').doc('ping').get(),
      cfg.timeoutMs,
      `Firestore (${mode})`,
    );
    return {
      mode,
      reached: true,
      outcome: snap.exists ? 'document_exists' : 'document_not_found',
      ms: Date.now() - started,
    };
  } catch (err) {
    return { mode, ...classifyFirestoreError(err, sanitize), ms: Date.now() - started };
  } finally {
    if (app) {
      await withTimeout(deleteApp(app), 3000, 'cleanup').catch(() => {});
    }
  }
}

async function hostReachability(host, timeoutMs, sanitize) {
  const started = Date.now();
  try {
    const res = await httpsRequest({ method: 'GET', host, path: '/', timeoutMs });
    return { ok: true, httpStatus: res.status, ms: Date.now() - started };
  } catch (err) {
    return { ok: false, error: sanitize(describeError(err)), ms: Date.now() - started };
  }
}

const FIRESTORE_SUCCESS = new Set(['document_not_found', 'document_exists']);

const FIRESTORE_HINTS = {
  permission_denied:
    'Связь есть, но у сервисного аккаунта нет прав. Проверьте роль «Cloud Datastore Viewer» (IAM в Google Cloud, проект remont-76b60) ' +
    'и что JSON-ключ создан именно для этого аккаунта.',
  unauthenticated:
    'Связь есть, но Google не принял ключ. Проверьте, что JSON вставлен целиком и ключ не удалён в консоли Google Cloud.',
  bad_credentials:
    'Связь есть, но Google отклонил ключ (invalid_grant). Возможные причины: ключ удалён/отключён в Google Cloud или JSON повреждён при вставке.',
  database_not_found:
    'Связь есть, но база данных не найдена. Проверьте FIREBASE_PROJECT_ID и что Firestore создан в режиме Native (default).',
  bad_key_file:
    'JSON-ключ не удаётся разобрать (часто ломается private_key при вставке). Вставьте файл ключа целиком, без правок.',
  unclassified:
    'Неклассифицированная ошибка. Пришлите отчёт целиком.',
  network_unreachable:
    'Firestore недоступен из функции по сети.',
};

async function checkFirestore(cfg, sa, sanitize) {
  const started = Date.now();

  if (!sa.ok) {
    return {
      status: 'FAIL',
      ms: 0,
      summary: 'Ключ сервисного аккаунта Firebase не прочитан',
      details: { config: sa.error },
      hint: `${sa.error} Проверьте переменную окружения FIREBASE_SA_JSON (секрет из Lockbox).`,
    };
  }

  const details = { serviceAccount: sa.info };

  // Любой HTTP-ответ (даже 404/401) означает, что хост достижим. Это отделяет
  // «сеть закрыта» от «ключ не принят»: ошибка получения OAuth-токена внутри gRPC
  // выглядит как UNAUTHENTICATED и без этой проверки могла бы скрыть сетевую проблему.
  const [grpc, firestoreHost, oauthHost] = await Promise.all([
    firestoreAttempt(cfg, sa, sanitize, false),
    hostReachability('firestore.googleapis.com', cfg.timeoutMs, sanitize),
    hostReachability('oauth2.googleapis.com', cfg.timeoutMs, sanitize),
  ]);
  details.grpc = grpc;
  details.hostReachability = {
    'firestore.googleapis.com': firestoreHost,
    'oauth2.googleapis.com': oauthHost,
  };

  if (
    grpc.reached === true &&
    (grpc.outcome === 'unauthenticated' || grpc.outcome === 'bad_credentials') &&
    oauthHost.ok === false
  ) {
    grpc.reached = false;
    grpc.outcome = 'network_unreachable';
    grpc.note = 'Ошибка авторизации на самом деле вызвана недоступностью oauth2.googleapis.com.';
  }

  if (grpc.reached === true) {
    const success = FIRESTORE_SUCCESS.has(grpc.outcome);
    return {
      status: success ? 'OK' : 'WARN',
      ms: Date.now() - started,
      summary: success
        ? 'Firestore отвечает по gRPC (документ не найден — это нормально, связь есть)'
        : `Firestore достижим по gRPC, но: ${grpc.outcome}`,
      details,
      hint: success ? null : FIRESTORE_HINTS[grpc.outcome] || null,
    };
  }

  if (grpc.reached === null) {
    return {
      status: 'FAIL',
      ms: Date.now() - started,
      summary: 'Проверка Firestore не удалась не из-за сети',
      details,
      hint: FIRESTORE_HINTS[grpc.outcome] || FIRESTORE_HINTS.unclassified,
    };
  }

  // gRPC недоступен по сети -> пробуем REST-режим клиента Firestore.
  const rest = await firestoreAttempt(cfg, sa, sanitize, true);
  details.rest = rest;

  if (rest.reached === true) {
    const success = FIRESTORE_SUCCESS.has(rest.outcome);
    return {
      status: 'WARN',
      ms: Date.now() - started,
      summary: success
        ? 'gRPC НЕ проходит, но REST-режим Firestore работает'
        : `gRPC не проходит; REST достижим, но: ${rest.outcome}`,
      details,
      hint:
        'Продолжать можно, но в основном backend Firestore нужно инициализировать с настройкой preferRest: true ' +
        '(в установленной версии @google-cloud/firestore опция поддерживается).' +
        (success ? '' : ` Дополнительно: ${FIRESTORE_HINTS[rest.outcome] || ''}`),
    };
  }

  return {
    status: 'FAIL',
    ms: Date.now() - started,
    summary: 'Firestore недоступен ни по gRPC, ни по REST',
    details,
    hint:
      'Функция не достучалась до Firestore ни одним способом. Пришлите отчёт целиком — нужно менять схему проверки прав.',
  };
}

// ---------------------------------------------------------------------------
// Проверка 3: Yandex Object Storage (HeadObject по несуществующему объекту)
// ---------------------------------------------------------------------------

function extractS3Error(body, sanitize) {
  const code = /<Code>([^<]+)<\/Code>/.exec(body || '');
  const message = /<Message>([^<]*)<\/Message>/.exec(body || '');
  return {
    code: code ? sanitize(code[1]) : null,
    message: message ? sanitize(message[1]) : null,
  };
}

function signS3(cfg, creds, { method, key, presign }) {
  const opts = {
    host: cfg.endpoint,
    method,
    service: 's3',
    region: cfg.region,
    path: `/${cfg.bucket}/${key}${presign ? '?X-Amz-Expires=300' : ''}`,
  };
  if (presign) opts.signQuery = true;
  aws4.sign(opts, creds);
  return opts;
}

async function s3Call(cfg, creds, spec) {
  const opts = signS3(cfg, creds, spec);
  return httpsRequest({
    method: spec.method,
    host: opts.host,
    path: opts.path,
    headers: opts.headers,
    timeoutMs: cfg.timeoutMs,
  });
}

const S3_KEY_MISMATCH_HINT =
  'Yandex не смог сопоставить подпись. Он не различает «нет такого ключа» и «неверный секрет», поэтому проверьте оба значения: ' +
  'S3_ACCESS_KEY — «Идентификатор ключа», S3_SECRET_KEY — «Секретный ключ» из ОДНОГО статического ключа сервисного аккаунта photos-signer, ' +
  'без пробелов и переводов строки; S3_REGION=ru-central1.';

const S3_HINTS = {
  InvalidAccessKeyId: S3_KEY_MISMATCH_HINT,
  SignatureDoesNotMatch: S3_KEY_MISMATCH_HINT,
  AccessDenied:
    'Ключ рабочий, но прав нет (AccessDenied). Назначьте сервисному аккаунту photos-signer роль storage.editor на бакет (или на каталог с бакетом).',
  NoSuchBucket:
    'Бакет не найден (NoSuchBucket). Проверьте S3_BUCKET=app-remont-photos и что бакет в том же облаке/каталоге.',
  RequestTimeTooSkewed:
    'Расхождение времени (RequestTimeTooSkewed). Повторите проверку; если повторяется — сообщите.',
};

async function checkS3(cfg, sanitize) {
  const started = Date.now();
  const details = {
    bucket: cfg.bucket,
    endpoint: cfg.endpoint,
    region: cfg.region,
    accessKey: describeSecret(cfg.rawKeyId),
    secretKey: describeSecret(cfg.rawSecret),
  };

  const keyId = cfg.rawKeyId.trim();
  const secret = cfg.rawSecret.trim();
  if (!keyId || !secret) {
    return {
      status: 'FAIL',
      ms: 0,
      summary: 'S3-ключи не заданы',
      details,
      hint: 'Заданы не все переменные: нужны S3_ACCESS_KEY и S3_SECRET_KEY (секреты из Lockbox).',
    };
  }
  if (details.accessKey.hasSurroundingWhitespace || details.secretKey.hasSurroundingWhitespace) {
    details.warning =
      'В значении ключа есть пробелы/переводы строки по краям. Для проверки они обрезаны, но в настройках функции их нужно убрать.';
  }

  const creds = { accessKeyId: keyId, secretAccessKey: secret };
  const rid = crypto.randomBytes(8).toString('hex');
  const headKey = `__probe__/does-not-exist-${rid}.jpg`;
  const presignKey = `__probe__/does-not-exist-presigned-${rid}.jpg`;

  // 3a. HeadObject, подпись в заголовке Authorization. Ожидаем 404.
  const headStarted = Date.now();
  let headOk = false;
  let headHint = null;
  try {
    const head = await s3Call(cfg, creds, { method: 'HEAD', key: headKey });
    let errorCode = null;
    if (head.status === 404) {
      headOk = true;
    } else if (head.status === 200) {
      headOk = true;
      details.note = 'Объект неожиданно существует (это не ошибка связи).';
    } else {
      // У HEAD нет тела ответа, поэтому код ошибки берём тем же запросом методом GET.
      const diag = await s3Call(cfg, creds, { method: 'GET', key: headKey });
      errorCode = extractS3Error(diag.body, sanitize);
      headHint = (errorCode.code && S3_HINTS[errorCode.code]) || null;
    }
    details.headObject = {
      ok: headOk,
      httpStatus: head.status,
      meaning: head.status === 404
        ? '404 — подпись принята, ключ и доступ работают'
        : head.status === 200
          ? '200 — объект найден'
          : 'ответ не 404',
      s3Error: errorCode,
      ms: Date.now() - headStarted,
    };
  } catch (err) {
    details.headObject = {
      ok: false,
      networkFailure: isNetworkError(err),
      error: sanitize(describeError(err)),
      ms: Date.now() - headStarted,
    };
  }

  // 3b. Presigned GET (подпись в query) — именно такой формат backend отдаёт клиентам.
  const presignStarted = Date.now();
  let presignOk = false;
  try {
    const res = await s3Call(cfg, creds, { method: 'GET', key: presignKey, presign: true });
    const s3Error = extractS3Error(res.body, sanitize);
    presignOk = res.status === 404 || res.status === 200;
    details.presignedGet = {
      ok: presignOk,
      httpStatus: res.status,
      meaning: res.status === 404
        ? '404 NoSuchKey — подпись в query принята'
        : 'ответ не 404',
      s3Error: res.status === 404 ? null : s3Error,
      ms: Date.now() - presignStarted,
    };
  } catch (err) {
    details.presignedGet = {
      ok: false,
      networkFailure: isNetworkError(err),
      error: sanitize(describeError(err)),
      ms: Date.now() - presignStarted,
    };
  }

  let status;
  let summary;
  let hint = null;
  if (headOk && presignOk) {
    status = 'OK';
    summary = 'Yandex S3 принимает подпись ключом (HEAD и presigned GET → 404)';
  } else if (headOk && !presignOk) {
    status = 'WARN';
    summary = 'HEAD прошёл, но presigned-подпись через query не принята';
    hint = 'Пришлите отчёт целиком: нужно разобраться, почему query-подпись не принимается.';
  } else if (details.headObject.networkFailure) {
    status = 'FAIL';
    summary = 'Yandex Object Storage недоступен по сети';
    hint = 'Проверьте S3_ENDPOINT=storage.yandexcloud.net и что функция не привязана к сети без выхода в интернет.';
  } else {
    const code = details.headObject.s3Error && details.headObject.s3Error.code;
    status = code === 'AccessDenied' ? 'WARN' : 'FAIL';
    summary = code
      ? `Yandex ответил ошибкой ${code}`
      : `Yandex ответил HTTP ${details.headObject.httpStatus}`;
    hint = headHint || 'Пришлите отчёт целиком.';
  }

  return { status, ms: Date.now() - started, summary, details, hint };
}

// ---------------------------------------------------------------------------
// Оркестрация и отчёт
// ---------------------------------------------------------------------------

async function runCheck(name, fn, sanitize) {
  const started = Date.now();
  try {
    return await fn();
  } catch (err) {
    return {
      status: 'FAIL',
      ms: Date.now() - started,
      summary: `Внутренняя ошибка зонда при проверке «${name}»`,
      details: { error: sanitize(describeError(err)) },
      hint: 'Это ошибка самого зонда. Пришлите отчёт целиком.',
    };
  }
}

function buildSummary(checks) {
  const statuses = {};
  for (const [name, check] of Object.entries(checks)) statuses[name] = check.status;
  const values = Object.values(statuses);

  if (values.every((s) => s === 'OK')) {
    return {
      verdict: 'PROCEED',
      message: 'Все три проверки прошли (OK / OK / OK). Схема реализуема, можно продолжать этап 1.',
      statuses,
    };
  }
  if (values.includes('FAIL')) {
    return {
      verdict: 'STOP',
      message: 'Есть проваленная проверка (FAIL). Не продолжайте — прочитайте hint в отчёте и пришлите отчёт мне.',
      statuses,
    };
  }
  return {
    verdict: 'PROCEED_WITH_NOTES',
    message: 'Связь есть, но по некоторым пунктам нужны правки или учёт (WARN). Прочитайте hint у каждой такой проверки.',
    statuses,
  };
}

async function runProbe(context) {
  const startedAt = new Date();
  const cfg = readConfig();
  const sa = loadServiceAccount(cfg);
  const sanitize = makeSanitizer(cfg, sa);

  const [verifyIdToken, firestoreRead, s3HeadObject] = await Promise.all([
    runCheck('verifyIdToken', () => checkVerifyIdToken(cfg, sanitize), sanitize),
    runCheck('firestoreRead', () => checkFirestore(cfg, sa, sanitize), sanitize),
    runCheck('s3HeadObject', () => checkS3(cfg, sanitize), sanitize),
  ]);
  const checks = { verifyIdToken, firestoreRead, s3HeadObject };

  const summary = buildSummary(checks);
  const nextSteps = Object.entries(checks)
    .filter(([, check]) => check.status !== 'OK' && check.hint)
    .map(([name, check]) => `${name}: ${check.hint}`);

  return {
    probe: 'remont-storage-probe',
    version: 1,
    startedAt: startedAt.toISOString(),
    totalMs: Date.now() - startedAt.getTime(),
    environment: {
      node: process.version,
      memoryLimitMb: (context && context.memoryLimitInMB) || null,
      functionVersion: (context && context.functionVersion) || null,
    },
    config: {
      firebaseProjectId: cfg.projectId,
      perStepTimeoutMs: cfg.timeoutMs,
      firebaseServiceAccountJson: sa.ok ? 'прочитан' : 'не прочитан',
    },
    summary,
    checks,
    nextSteps,
  };
}

async function handler(event, context) {
  let report;
  try {
    report = await runProbe(context);
  } catch (err) {
    report = {
      probe: 'remont-storage-probe',
      version: 1,
      summary: {
        verdict: 'STOP',
        message: 'Зонд аварийно завершился до проверок. Пришлите этот отчёт.',
      },
      fatal: String(err && err.message ? err.message : err).slice(0, 300),
    };
  }

  console.log(JSON.stringify({
    probe: 'summary',
    verdict: report.summary && report.summary.verdict,
    statuses: report.summary && report.summary.statuses,
    totalMs: report.totalMs,
  }));

  // При вызове через HTTP (API Gateway / integration=raw) нужен HTTP-ответ,
  // при вызове из консоли («Тестирование») — просто объект отчёта.
  if (event && typeof event === 'object' && event.httpMethod) {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(report, null, 2),
    };
  }
  return report;
}

module.exports = { handler };
