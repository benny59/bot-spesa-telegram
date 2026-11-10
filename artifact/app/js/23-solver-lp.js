"use strict";
// Two-phase primal simplex on a dense tableau. minimize c·x  s.t. rows (a·x <=|>=|= b), x >= 0.
// Dantzig pricing with Bland's rule after a run of degenerate pivots (anti-cycling).
function lpSolve(c, rows, maxIter){
  const EPS = 1e-9, m = rows.length, n = c.length; maxIter = maxIter || 50000;
  const R = rows.map(r => { let a = r.a, b = r.b, op = r.op; if (b < 0){ a = Array.from(a, v => -v); b = -b; op = op === "<=" ? ">=" : op === ">=" ? "<=" : "="; } return {a, b, op}; });
  let nS = 0, nA = 0; for (const r of R){ if (r.op !== "=") nS++; if (r.op !== "<=") nA++; }
  const W = n + nS + nA + 1, RHS = W - 1;
  const T = new Array(m), basis = new Int32Array(m), isArt = new Uint8Array(W);
  let si = n, ai = n + nS;
  for (let i = 0; i < m; i++){
    const row = new Float64Array(W), r = R[i];
    for (let j = 0; j < n; j++) row[j] = r.a[j] || 0;
    row[RHS] = r.b;
    if (r.op === "<="){ row[si] = 1; basis[i] = si++; }
    else if (r.op === ">="){ row[si++] = -1; row[ai] = 1; isArt[ai] = 1; basis[i] = ai++; }
    else { row[ai] = 1; isArt[ai] = 1; basis[i] = ai++; }
    T[i] = row;
  }
  let iters = 0;
  function pivot(l, e, z){
    const pr = T[l], pv = pr[e];
    for (let j = 0; j < W; j++) if (pr[j] !== 0) pr[j] /= pv;
    const nz = []; for (let j = 0; j < W; j++) if (pr[j] !== 0) nz.push(j);
    for (let i = 0; i < m; i++){ if (i === l) continue; const row = T[i], f = row[e]; if (f !== 0){ for (const j of nz) row[j] -= f*pr[j]; row[e] = 0; } }
    const f = z[e]; if (f !== 0){ for (const j of nz) z[j] -= f*pr[j]; z[e] = 0; }
    basis[l] = e;
  }
  function run(cost, allowed){
    const z = new Float64Array(W);
    for (let j = 0; j < RHS; j++) z[j] = cost[j] || 0;
    for (let i = 0; i < m; i++){ const cb = cost[basis[i]] || 0; if (cb !== 0){ const row = T[i]; for (let j = 0; j < W; j++) if (row[j] !== 0) z[j] -= cb*row[j]; } }
    let degen = 0;
    while (iters++ < maxIter){
      const bland = degen > 30;
      let e = -1, best = -1e-9;
      for (let j = 0; j < RHS; j++){ if (!allowed[j]) continue; const v = z[j]; if (v < best){ e = j; if (bland) break; best = v; } }
      if (e < 0) return {status:"optimal", z};
      let l = -1, minR = Infinity;
      for (let i = 0; i < m; i++){ const a = T[i][e]; if (a > EPS){ const r = T[i][RHS]/a; if (r < minR - 1e-11 || (Math.abs(r - minR) <= 1e-11 && (l < 0 || basis[i] < basis[l]))){ minR = r; l = i; } } }
      if (l < 0) return {status:"unbounded", z};
      degen = minR < 1e-11 ? degen + 1 : 0;
      pivot(l, e, z);
    }
    return {status:"iterations", z};
  }
  const all = new Uint8Array(RHS).fill(1);
  if (nA){
    const c1 = new Float64Array(RHS); for (let j = 0; j < RHS; j++) c1[j] = isArt[j] ? 1 : 0;
    const p1 = run(c1, all);
    let infeas = 0; for (let i = 0; i < m; i++) if (isArt[basis[i]]) infeas += T[i][RHS];
    if (p1.status !== "optimal" || infeas > 1e-6) return {status: p1.status !== "optimal" ? p1.status : "infeasible", x: null, iters};
    // drive artificial variables that stayed basic at zero out of the basis
    for (let i = 0; i < m; i++) if (isArt[basis[i]]){ for (let j = 0; j < RHS; j++) if (!isArt[j] && Math.abs(T[i][j]) > 1e-9){ pivot(i, j, new Float64Array(W)); break; } }
  }
  const allowed = new Uint8Array(RHS); for (let j = 0; j < RHS; j++) allowed[j] = isArt[j] ? 0 : 1;
  const c2 = new Float64Array(RHS); for (let j = 0; j < n; j++) c2[j] = c[j] || 0;
  const p2 = run(c2, allowed);
  const x = new Float64Array(n); for (let i = 0; i < m; i++) if (basis[i] < n) x[basis[i]] = Math.max(0, T[i][RHS]);
  let obj = 0; for (let j = 0; j < n; j++) obj += (c[j]||0)*x[j];
  return {status: p2.status, x: Array.from(x), obj, iters};
}
