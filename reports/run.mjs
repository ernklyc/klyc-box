#!/usr/bin/env node
/**
 * Reads every player report with the project's admin rights and writes the public totals file.
 *
 *   npm install firebase-admin           (once, in this folder)
 *   export GOOGLE_APPLICATION_CREDENTIALS=<service account key file>
 *   node run.mjs [output file]           (default: reports.json)
 *
 * The reports themselves never leave Firestore; only the totals of games with enough reports do.
 */
import fs from "node:fs";
import { aggregate } from "./aggregate.mjs";

const { initializeApp, applicationDefault } = await import("firebase-admin/app");
const { getFirestore } = await import("firebase-admin/firestore");

initializeApp({ credential: applicationDefault() });
const snapshot = await getFirestore().collection("reports").get();
const reports = snapshot.docs.map((d) => d.data());
const out = aggregate(reports);
const file = process.argv[2] ?? "reports.json";
fs.writeFileSync(file, JSON.stringify(out));
console.log(`${reports.length} reports, ${Object.keys(out.games).length} games published -> ${file}`);
