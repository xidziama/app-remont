/**
 * Firestore Security Rules unit tests — APP_Remont
 *
 * Requires Firebase Emulator running on:
 *   Auth:      9099
 *   Firestore: 8080
 *
 * Override host/port via env:
 *   FIRESTORE_HOST=127.0.0.1  FIRESTORE_PORT=8080
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import assert from 'assert';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

import {
  collection,
  collectionGroup,
  doc,
  deleteDoc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  query,
  where,
  writeBatch,
  arrayUnion,
  serverTimestamp,
} from 'firebase/firestore';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const __dir = dirname(fileURLToPath(import.meta.url));
const RULES = readFileSync(resolve(__dir, '../firestore.rules'), 'utf8');

const PROJECT_ID   = 'remont-76b60';
const FS_HOST      = process.env.FIRESTORE_HOST || '127.0.0.1';
const FS_PORT      = parseInt(process.env.FIRESTORE_PORT || '8080', 10);

// ---------------------------------------------------------------------------
// Fixture IDs
// ---------------------------------------------------------------------------
const COMPANY_ID   = 'c1';
const PROJ_ID      = 'p1';
const PROJ_OTHER   = 'p_other';
const STAGE_ID     = 's1';
const INV_ID       = 'inv_w1';
const EXP_UNPAID_ID = 'exp_unpaid';
const EXP_PAID_ID   = 'exp_paid';

const OWNER_UID    = 'owner1';
const OWNER_EMAIL  = 'owner@remont.test';

const MGR_UID      = 'mgr1';
const MGR_EMAIL    = 'mgr@remont.test';

const MGR2_UID     = 'mgr2';           // member but assigned to NO project
const MGR2_EMAIL   = 'mgr2@remont.test';

const WORKER_UID   = 'worker1';
const WORKER_EMAIL = 'worker@remont.test';

const WORKER2_UID   = 'worker2';         // assigned to STAGE_ID, but author of nothing
const WORKER2_EMAIL = 'worker2@remont.test';

const CLIENT_UID   = 'client1';
const CLIENT_EMAIL = 'client@remont.test';

const OUT_UID      = 'outsider1';
const OUT_EMAIL    = 'outsider@remont.test';

// ---------------------------------------------------------------------------
// Test environment (shared across tests)
// ---------------------------------------------------------------------------
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host: FS_HOST, port: FS_PORT, rules: RULES },
  });
});

after(async () => {
  await testEnv.cleanup();
});

// ---------------------------------------------------------------------------
// Seed Firestore via admin SDK (bypasses rules)
// ---------------------------------------------------------------------------
async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const iso = () => new Date().toISOString();

    // Company
    await setDoc(doc(db, 'companies', COMPANY_ID), {
      ownerId: OWNER_UID,
      name: 'Рога и Копыта',
      code: 'RK',
      companyCode: 'RK',
      status: 'active',
    });

    // Memberships
    const memberBase = (uid, email, role, projects = []) => ({
      uid, companyId: COMPANY_ID, companyName: 'Рога и Копыта',
      email, displayName: email, role,
      canCreateProjects: false, assignedProjectIds: projects,
      active: true, createdAt: iso(),
    });
    await setDoc(doc(db, `companies/${COMPANY_ID}/members`, OWNER_UID),
      { ...memberBase(OWNER_UID, OWNER_EMAIL, 'owner'), canCreateProjects: true });
    await setDoc(doc(db, `companies/${COMPANY_ID}/members`, MGR_UID),
      memberBase(MGR_UID, MGR_EMAIL, 'manager', [PROJ_ID]));
    await setDoc(doc(db, `companies/${COMPANY_ID}/members`, MGR2_UID),
      memberBase(MGR2_UID, MGR2_EMAIL, 'manager', []));
    // NOTE: worker1 has NO membership — it will be created by the batch test

    // Project1 — company COMPANY_ID, all participants pre-seeded except worker
    await setDoc(doc(db, 'projects', PROJ_ID), {
      ownerId: OWNER_UID,
      companyId: COMPANY_ID,
      title: 'Объект №1',
      status: 'inProgress',
      participantIds: [OWNER_UID, MGR_UID, WORKER_UID, WORKER2_UID, CLIENT_UID],
      managerIds: [MGR_UID],
      managerNames: ['mgr@remont.test'],
      workerIds: [WORKER_UID, WORKER2_UID],
      workerNames: ['worker@remont.test', 'worker2@remont.test'],
      clientIds: [CLIENT_UID],
      clientNames: ['client@remont.test'],
    });

    // Project2 — different company
    await setDoc(doc(db, 'projects', PROJ_OTHER), {
      ownerId: 'other_owner',
      companyId: 'company_other',
      title: 'Чужой объект',
      status: 'inProgress',
      participantIds: ['other_owner'],
      managerIds: [], workerIds: [], clientIds: [],
    });

    // Stage
    await setDoc(doc(db, `projects/${PROJ_ID}/stages`, STAGE_ID), {
      projectId: PROJ_ID,
      title: 'Этап 1',
      status: 'not_started',
      assignedUserIds: [WORKER_UID, WORKER2_UID],
      assignedUserNames: ['worker@remont.test', 'worker2@remont.test'],
      photosCount: 0,
      updatedAt: iso(),
    });

    // Stage photo (real production model — projects/{id}/stages/{id}/photos)
    await setDoc(doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, 'sph1'), {
      projectId: PROJ_ID,
      stageId: STAGE_ID,
      type: 'progress',
      downloadUrl: 'https://x.com/sph1.jpg',
      storagePath: 'projects/p1/stages/s1/photos/sph1.jpg',
      uploadedBy: 'worker@remont.test',
      createdAt: iso(),
    });

    // Expense (chek) — unpaid, created by worker1, linked to STAGE_ID, plus
    // its mirror receipt photo under stages/{STAGE_ID}/photos (same id).
    await setDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
      id: EXP_UNPAID_ID,
      projectId: PROJ_ID,
      stageId: STAGE_ID,
      stageTitle: 'Этап 1',
      amount: 1000,
      category: 'materials',
      date: iso(),
      createdAt: iso(),
      createdBy: WORKER_UID,
      comment: 'Цемент',
      isPaid: false,
    });
    await setDoc(
      doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_UNPAID_ID),
      {
        id: EXP_UNPAID_ID,
        projectId: PROJ_ID,
        stageId: STAGE_ID,
        type: 'receipt',
        downloadUrl: 'https://x.com/exp_unpaid.jpg',
        storagePath: 'projects/p1/stages/s1/photos/exp_unpaid.jpg',
        comment: 'Цемент',
        amount: 1000,
        expenseId: EXP_UNPAID_ID,
        receiptCategory: 'materials',
        uploadedBy: 'worker@remont.test',
        createdAt: iso(),
        isPaid: false,
      },
    );

    // Expense (chek) — PAID, created by worker1, linked to STAGE_ID, plus its
    // mirror receipt photo. Used to confirm the "frozen for everyone" rule.
    await setDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID), {
      id: EXP_PAID_ID,
      projectId: PROJ_ID,
      stageId: STAGE_ID,
      stageTitle: 'Этап 1',
      amount: 500,
      category: 'tools',
      date: iso(),
      createdAt: iso(),
      createdBy: WORKER_UID,
      comment: 'Перфоратор',
      isPaid: true,
      paidAt: iso(),
      paidBy: OWNER_UID,
    });
    await setDoc(
      doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_PAID_ID),
      {
        id: EXP_PAID_ID,
        projectId: PROJ_ID,
        stageId: STAGE_ID,
        type: 'receipt',
        downloadUrl: 'https://x.com/exp_paid.jpg',
        storagePath: 'projects/p1/stages/s1/photos/exp_paid.jpg',
        comment: 'Перфоратор',
        amount: 500,
        expenseId: EXP_PAID_ID,
        receiptCategory: 'tools',
        uploadedBy: 'worker@remont.test',
        createdAt: iso(),
        isPaid: true,
        paidAt: iso(),
        paidBy: OWNER_UID,
      },
    );

    // Photo and message
    await setDoc(doc(db, `projects/${PROJ_ID}/photos`, 'ph1'), {
      projectId: PROJ_ID, url: 'https://x.com/ph.jpg', type: 'progress',
    });
    await setDoc(doc(db, `projects/${PROJ_ID}/messages`, 'msg1'), {
      senderId: OWNER_UID, text: 'Привет', type: 'text',
    });

    // Pending invitation for worker1
    await setDoc(doc(db, `companies/${COMPANY_ID}/invitations`, INV_ID), {
      companyId: COMPANY_ID,
      companyName: 'Рога и Копыта',
      email: WORKER_EMAIL,
      role: 'worker',
      status: 'pending',
      projectId: PROJ_ID,
      projectTitle: 'Объект №1',
      stageIds: [STAGE_ID],
      stageTitles: ['Этап 1'],
      createdAt: iso(),
      createdBy: OWNER_UID,
    });
  });
}

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed();
});

// ---------------------------------------------------------------------------
// Context helpers
// ---------------------------------------------------------------------------
const ctx = {
  owner:    () => testEnv.authenticatedContext(OWNER_UID,  { email: OWNER_EMAIL }),
  manager:  () => testEnv.authenticatedContext(MGR_UID,    { email: MGR_EMAIL }),
  manager2: () => testEnv.authenticatedContext(MGR2_UID,   { email: MGR2_EMAIL }),
  worker:   () => testEnv.authenticatedContext(WORKER_UID, { email: WORKER_EMAIL }),
  worker2:  () => testEnv.authenticatedContext(WORKER2_UID, { email: WORKER2_EMAIL }),
  client:   () => testEnv.authenticatedContext(CLIENT_UID, { email: CLIENT_EMAIL }),
  outsider: () => testEnv.authenticatedContext(OUT_UID,    { email: OUT_EMAIL }),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('Firestore Security Rules — APP_Remont', () => {

  // -------------------------------------------------------------------------
  // S1 — owner: query own-company projects
  // -------------------------------------------------------------------------
  it('S1 — owner: query projects WHERE companyId==X → allow', async () => {
    const db = ctx.owner().firestore();
    const q  = query(collection(db, 'projects'), where('companyId', '==', COMPANY_ID));
    const snap = await assertSucceeds(getDocs(q));
    assert.ok(snap.size >= 1, 'Expected at least one project');
  });

  // -------------------------------------------------------------------------
  // S2 — owner: read project of another company
  // -------------------------------------------------------------------------
  it('S2 — owner: read project of another company → deny', async () => {
    const db = ctx.owner().firestore();
    await assertFails(getDoc(doc(db, 'projects', PROJ_OTHER)));
  });

  // -------------------------------------------------------------------------
  // S3 — manager in participantIds reads project
  // -------------------------------------------------------------------------
  it('S3 — manager (in participantIds): read project → allow', async () => {
    const db = ctx.manager().firestore();
    const snap = await assertSucceeds(getDoc(doc(db, 'projects', PROJ_ID)));
    assert.ok(snap.exists(), 'Project document must exist');
  });

  // -------------------------------------------------------------------------
  // S4 — manager member but NOT in any participantIds: query returns empty
  // -------------------------------------------------------------------------
  it('S4 — manager (no projects): query participantIds array-contains → empty, no error', async () => {
    const db = ctx.manager2().firestore();
    const q  = query(
      collection(db, 'projects'),
      where('participantIds', 'array-contains', MGR2_UID),
    );
    const snap = await assertSucceeds(getDocs(q));
    assert.strictEqual(snap.size, 0, 'Expected 0 results — manager has no projects');
  });

  // -------------------------------------------------------------------------
  // S5 — worker in participantIds + workerIds reads project
  // -------------------------------------------------------------------------
  it('S5 — worker (in workerIds): read project → allow', async () => {
    const db = ctx.worker().firestore();
    const snap = await assertSucceeds(getDoc(doc(db, 'projects', PROJ_ID)));
    assert.ok(snap.exists());
  });

  // -------------------------------------------------------------------------
  // S6a — client reads project
  // -------------------------------------------------------------------------
  it('S6a — client (in clientIds): read project → allow', async () => {
    const db = ctx.client().firestore();
    await assertSucceeds(getDoc(doc(db, 'projects', PROJ_ID)));
  });

  // -------------------------------------------------------------------------
  // S6b — client changes status client_review → closed
  // -------------------------------------------------------------------------
  it('S6b — client: status client_review → closed → allow', async () => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'projects', PROJ_ID), {
        status: 'client_review',
      });
    });
    const db = ctx.client().firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'projects', PROJ_ID), { status: 'closed' }),
    );
  });

  // -------------------------------------------------------------------------
  // S6c — client tries to change status to arbitrary value → deny
  // -------------------------------------------------------------------------
  it('S6c — client: status → arbitrary value → deny', async () => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'projects', PROJ_ID), {
        status: 'client_review',
      });
    });
    const db = ctx.client().firestore();
    await assertFails(
      updateDoc(doc(db, 'projects', PROJ_ID), { status: 'inProgress' }),
    );
  });

  // -------------------------------------------------------------------------
  // S7 — batch _acceptCompanyInvitation (worker role)
  //
  // Replicates exactly what project_repository.dart does:
  //   1  SET   companies/{C}/members/{worker}  — membership with acceptedInvitationId
  //   2  UPDATE companies/{C}/invitations/{I}   — status→accepted
  //   3  UPDATE projects/{P}                    — workerIds/workerNames/participantIds
  //   4  UPDATE projects/{P}/stages/{S}         — assignedUserIds/assignedUserNames/updatedAt
  //   5  SET   projects/{P}/timeline/{e1}       — invitationAccepted, stageId=''
  //   6  SET   projects/{P}/timeline/{e2}       — participantAdded,   stageId=''
  //   7  SET   projects/{P}/timeline/{e3}       — workerAssignedToStage, stageId=S
  //   8  SET   users/{owner}/notifications/{n1} — invitationAccepted for owner
  //   9  SET   users/{worker}/notifications/{n2} — workerAssignedToStage for worker (includeCurrentUser=true)
  // -------------------------------------------------------------------------
  it('S7 — batch accept invitation (worker): _acceptCompanyInvitation batch → allow', async () => {
    // Remove worker from project so the batch adds them fresh
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      await updateDoc(doc(db, 'projects', PROJ_ID), {
        workerIds:      [],
        workerNames:    [],
        participantIds: [OWNER_UID, MGR_UID, CLIENT_UID],
      });
      await updateDoc(doc(db, `projects/${PROJ_ID}/stages`, STAGE_ID), {
        assignedUserIds:   [],
        assignedUserNames: [],
      });
    });

    const db  = ctx.worker().firestore();
    const bat = writeBatch(db);
    const iso = new Date().toISOString();

    // 1 — membership
    bat.set(
      doc(db, `companies/${COMPANY_ID}/members`, WORKER_UID),
      {
        uid:                   WORKER_UID,
        companyId:             COMPANY_ID,
        companyName:           'Рога и Копыта',
        email:                 WORKER_EMAIL,
        displayName:           'Worker User',
        role:                  'worker',
        canCreateProjects:     false,
        assignedProjectIds:    [PROJ_ID],
        active:                true,
        createdAt:             iso,
        acceptedInvitationId:  INV_ID,
      },
      { merge: true },
    );

    // 2 — invitation → accepted
    bat.update(
      doc(db, `companies/${COMPANY_ID}/invitations`, INV_ID),
      {
        status:     'accepted',
        acceptedAt: serverTimestamp(),
        acceptedBy: WORKER_UID,
      },
    );

    // 3 — project access
    bat.update(
      doc(db, 'projects', PROJ_ID),
      {
        workerIds:      arrayUnion(WORKER_UID),
        workerNames:    arrayUnion('Worker User'),
        participantIds: arrayUnion(WORKER_UID),
      },
    );

    // 4 — stage assignment
    bat.update(
      doc(db, `projects/${PROJ_ID}/stages`, STAGE_ID),
      {
        assignedUserIds:   arrayUnion(WORKER_UID),
        assignedUserNames: arrayUnion('Worker User'),
        updatedAt:         iso,
      },
    );

    // 5 — timeline: invitationAccepted (stageId='')
    bat.set(
      doc(db, `projects/${PROJ_ID}/timeline`, 'evt1'),
      {
        projectId: PROJ_ID,
        stageId:   '',
        type:      'invitation_accepted',
        userId:    WORKER_UID,
        createdAt: iso,
      },
    );

    // 6 — timeline: participantAdded (stageId='')
    bat.set(
      doc(db, `projects/${PROJ_ID}/timeline`, 'evt2'),
      {
        projectId: PROJ_ID,
        stageId:   '',
        type:      'participant_added',
        userId:    WORKER_UID,
        createdAt: iso,
      },
    );

    // 7 — timeline: workerAssignedToStage (stageId=STAGE_ID)
    bat.set(
      doc(db, `projects/${PROJ_ID}/timeline`, 'evt3'),
      {
        projectId: PROJ_ID,
        stageId:   STAGE_ID,
        type:      'worker_assigned_to_stage',
        userId:    WORKER_UID,
        createdAt: iso,
      },
    );

    // 8 — notification for owner (companyId branch in validNotificationCreate)
    bat.set(
      doc(db, `users/${OWNER_UID}/notifications`, 'n1'),
      {
        id:           'n1',
        userId:       OWNER_UID,
        type:         'invitation_accepted',
        title:        'Пользователь принял приглашение',
        message:      'Worker User присоединился к компании.',
        isRead:       false,
        createdAt:    iso,
        companyId:    COMPANY_ID,
        projectId:    PROJ_ID,
        projectTitle: 'Объект №1',
      },
    );

    // 9 — notification for worker themselves (userId==uid() branch)
    bat.set(
      doc(db, `users/${WORKER_UID}/notifications`, 'n2'),
      {
        id:           'n2',
        userId:       WORKER_UID,
        type:         'worker_assigned_to_stage',
        title:        'Вам назначен новый этап',
        message:      'Объект "Объект №1": Этап 1.',
        isRead:       false,
        createdAt:    iso,
        companyId:    COMPANY_ID,
        projectId:    PROJ_ID,
        projectTitle: 'Объект №1',
      },
    );

    await assertSucceeds(bat.commit());
  });

  // -------------------------------------------------------------------------
  // S8a — assigned worker reads stages / photos / chat
  // -------------------------------------------------------------------------
  it('S8a — worker (assigned): reads stages + photos + messages → allow', async () => {
    const db = ctx.worker().firestore();
    await assertSucceeds(getDoc(doc(db, `projects/${PROJ_ID}/stages`,   STAGE_ID)));
    await assertSucceeds(getDoc(doc(db, `projects/${PROJ_ID}/photos`,   'ph1')));
    await assertSucceeds(getDoc(doc(db, `projects/${PROJ_ID}/messages`, 'msg1')));
  });

  // -------------------------------------------------------------------------
  // S8b — outsider reads stages / photos / chat → deny
  // -------------------------------------------------------------------------
  it('S8b — outsider: reads stages + photos + messages → deny', async () => {
    const db = ctx.outsider().firestore();
    await assertFails(getDoc(doc(db, `projects/${PROJ_ID}/stages`,   STAGE_ID)));
    await assertFails(getDoc(doc(db, `projects/${PROJ_ID}/photos`,   'ph1')));
    await assertFails(getDoc(doc(db, `projects/${PROJ_ID}/messages`, 'msg1')));
  });

  // -------------------------------------------------------------------------
  // S9 — regression: createCompany batch (company doc + owner membership doc
  // written atomically, exactly as project_repository.dart does), then the
  // same owner queries projects WHERE companyId == X.
  //
  // This reproduces the production bug report: a company whose `members`
  // subcollection stayed empty after creation caused PERMISSION_DENIED for
  // the owner's own project list query. If createCompany really writes both
  // documents in one batch (current code does), this must pass.
  // -------------------------------------------------------------------------
  it('S9 — createCompany batch (company + owner membership) then owner lists own projects → allow', async () => {
    const NEW_COMPANY_ID = 'c_new9';
    const NEW_OWNER_UID = 'owner9';
    const NEW_OWNER_EMAIL = 'owner9@remont.test';
    const iso = new Date().toISOString();

    const db = testEnv
      .authenticatedContext(NEW_OWNER_UID, { email: NEW_OWNER_EMAIL })
      .firestore();
    const bat = writeBatch(db);

    // Same shape as ProjectRepository.createCompany batch.
    bat.set(doc(db, 'companies', NEW_COMPANY_ID), {
      name: 'Новая компания',
      code: 'NEW9',
      companyCode: 'NEW9',
      ownerId: NEW_OWNER_UID,
      status: 'active',
      createdAt: iso,
    });
    bat.set(doc(db, `companies/${NEW_COMPANY_ID}/members`, NEW_OWNER_UID), {
      companyId: NEW_COMPANY_ID,
      companyName: 'Новая компания',
      uid: NEW_OWNER_UID,
      email: NEW_OWNER_EMAIL,
      displayName: 'Owner Nine',
      role: 'owner',
      canCreateProjects: true,
      assignedProjectIds: [],
      active: true,
      createdAt: iso,
    });
    bat.set(
      doc(db, 'users', NEW_OWNER_UID),
      {
        uid: NEW_OWNER_UID,
        email: NEW_OWNER_EMAIL,
        displayName: 'Owner Nine',
        baseRole: 'user',
        updatedAt: iso,
        createdAt: iso,
      },
      { merge: true },
    );

    await assertSucceeds(bat.commit());

    // A project for the new company, seeded directly (project-create rules
    // are out of scope for this regression test — we only care about read).
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'projects', 'p_new9'), {
        ownerId: NEW_OWNER_UID,
        companyId: NEW_COMPANY_ID,
        title: 'Проект новой компании',
        status: 'inProgress',
        participantIds: [NEW_OWNER_UID],
        managerIds: [], managerNames: [],
        workerIds: [], workerNames: [],
        clientIds: [], clientNames: [],
      });
    });

    const q = query(
      collection(db, 'projects'),
      where('companyId', '==', NEW_COMPANY_ID),
    );
    const snap = await assertSucceeds(getDocs(q));
    assert.strictEqual(snap.size, 1, 'Owner must see the newly created company project');
  });

  // -------------------------------------------------------------------------
  // S10 — regression: общая галерея фото объекта читает через
  // collectionGroup('photos').where('projectId', isEqualTo: X) — нужен
  // отдельный /{path=**}/photos/{photoId} bootstrap-rule, нестед-правило
  // projects/{id}/stages/{stageId}/photos/{photoId} его не покрывает.
  // -------------------------------------------------------------------------
  it('S10a — worker (project participant): collectionGroup photos by projectId → allow', async () => {
    const db = ctx.worker().firestore();
    const q = query(
      collectionGroup(db, 'photos'),
      where('projectId', '==', PROJ_ID),
    );
    const snap = await assertSucceeds(getDocs(q));
    assert.ok(snap.size >= 1, 'Worker must see at least the seeded stage photo');
  });

  it('S10b — outsider: collectionGroup photos by projectId → deny', async () => {
    const db = ctx.outsider().firestore();
    const q = query(
      collectionGroup(db, 'photos'),
      where('projectId', '==', PROJ_ID),
    );
    await assertFails(getDocs(q));
  });

  // -------------------------------------------------------------------------
  // E — expenses: edit/delete permission matrix.
  //
  // Matrix under test (see firestore.rules match /expenses/{expenseId}):
  //   unpaid  + author           → allow
  //   unpaid  + author of ANOTHER receipt (not this one) → deny
  //   unpaid  + owner/manager    → allow
  //   PAID    + owner/manager    → deny (frozen for everyone, key regression)
  //   PAID    + author           → deny (frozen for everyone)
  //   any     + client           → deny
  // The mirror doc at stages/{STAGE_ID}/photos/{expenseId} must follow the
  // same matrix (E11-E14).
  // -------------------------------------------------------------------------

  it('E1 — author: edit own unpaid expense (amount/category/comment) → allow', async () => {
    const db = ctx.worker().firestore();
    await assertSucceeds(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
        amount: 1200,
        category: 'delivery',
        comment: 'Цемент + доставка',
      }),
    );
  });

  it('E2 — author: delete own unpaid expense → allow', async () => {
    const db = ctx.worker().firestore();
    await assertSucceeds(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID)),
    );
  });

  it('E3 — worker2 (not the author): edit someone else\'s unpaid expense → deny', async () => {
    const db = ctx.worker2().firestore();
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
        amount: 1,
      }),
    );
  });

  it('E4 — worker2 (not the author): delete someone else\'s unpaid expense → deny', async () => {
    const db = ctx.worker2().firestore();
    await assertFails(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID)),
    );
  });

  it('E5 — owner: edit/delete any unpaid expense → allow', async () => {
    const db = ctx.owner().firestore();
    await assertSucceeds(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
        amount: 900,
      }),
    );
    await assertSucceeds(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID)),
    );
  });

  it('E6 — manager: edit any unpaid expense of own company project → allow', async () => {
    const db = ctx.manager().firestore();
    await assertSucceeds(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
        comment: 'Проверено прорабом',
      }),
    );
  });

  it('E7 — owner: edit PAID expense → deny (key regression — frozen for everyone)', async () => {
    const db = ctx.owner().firestore();
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID), {
        amount: 1,
      }),
    );
  });

  it('E8 — owner: delete PAID expense → deny (key regression — frozen for everyone)', async () => {
    const db = ctx.owner().firestore();
    await assertFails(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID)),
    );
  });

  it('E9 — manager: edit/delete PAID expense → deny', async () => {
    const db = ctx.manager().firestore();
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID), {
        comment: 'x',
      }),
    );
    await assertFails(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID)),
    );
  });

  it('E10 — author: edit/delete own PAID expense → deny', async () => {
    const db = ctx.worker().firestore();
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID), {
        amount: 1,
      }),
    );
    await assertFails(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID)),
    );
  });

  it('E11 — client: edit/delete unpaid or paid expense → deny', async () => {
    const db = ctx.client().firestore();
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
        amount: 1,
      }),
    );
    await assertFails(
      deleteDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID)),
    );
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_PAID_ID), {
        amount: 1,
      }),
    );
  });

  it('E12 — author: edit own unpaid expense trying to also flip isPaid → deny (field not allowed)', async () => {
    const db = ctx.worker().firestore();
    await assertFails(
      updateDoc(doc(db, `projects/${PROJ_ID}/expenses`, EXP_UNPAID_ID), {
        amount: 1200,
        isPaid: true,
      }),
    );
  });

  // -------------------------------------------------------------------------
  // Mirror receipt photo at stages/{STAGE_ID}/photos/{expenseId} must follow
  // the exact same matrix as the expense document above.
  // -------------------------------------------------------------------------

  it('E13 — author: edit own unpaid receipt mirror photo → allow', async () => {
    const db = ctx.worker().firestore();
    await assertSucceeds(
      updateDoc(
        doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_UNPAID_ID),
        { amount: 1200, comment: 'Цемент + доставка' },
      ),
    );
  });

  it('E14 — worker2 (not author): edit/delete someone else\'s unpaid receipt mirror photo → deny', async () => {
    const db = ctx.worker2().firestore();
    await assertFails(
      updateDoc(
        doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_UNPAID_ID),
        { amount: 1 },
      ),
    );
    await assertFails(
      deleteDoc(
        doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_UNPAID_ID),
      ),
    );
  });

  it('E15 — owner: edit/delete PAID receipt mirror photo → deny (key regression)', async () => {
    const db = ctx.owner().firestore();
    await assertFails(
      updateDoc(
        doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_PAID_ID),
        { amount: 1 },
      ),
    );
    await assertFails(
      deleteDoc(
        doc(db, `projects/${PROJ_ID}/stages/${STAGE_ID}/photos`, EXP_PAID_ID),
      ),
    );
  });
});
