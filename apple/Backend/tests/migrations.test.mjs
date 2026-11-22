import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {maskEmail} from '../src/rules.mjs';

test('Legacy masks preserve accounts and results until Apple refreshes the five-character name', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec(readFileSync(new URL('../migrations/0001_coachability.sql', import.meta.url), 'utf8'));
    db.exec("INSERT INTO users VALUES('person','private-apple-id','ra•••m',123);");
    db.exec("INSERT INTO play_sessions VALUES('session','person','tennis');");
    db.exec("INSERT INTO coach_points VALUES('point','person','session',1,1,0,4,'[]',0,0,456);");
    db.exec(readFileSync(new URL('../migrations/0002_email_username_masks.sql', import.meta.url), 'utf8'));
    assert.equal(db.prepare("SELECT email_mask FROM users WHERE id='person'").get().email_mask, 'ra•••');
    assert.equal(db.prepare('SELECT cp FROM coach_points').get().cp, 4);
    db.prepare("UPDATE users SET email_mask=? WHERE apple_sub=?").run(maskEmail('rahul@example.com'), 'private-apple-id');
    assert.equal(db.prepare('SELECT email_mask FROM users').get().email_mask, 'rahul');
  } finally { db.close(); }
});
