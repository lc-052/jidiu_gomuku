'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {GameRules}=require('./game_rules');
test('captures, restores captures on undo, and rejects suicide',()=>{
 const g=new GameRules('go',9);g.play(0,1);g.play(0,0);g.play(1,0);
 assert.equal(g.captures.black,1);assert.equal(g.board[0][0],null);
 assert.throws(()=>g.play(0,0),/禁入点/);
 g.undo(1);assert.equal(g.board[0][0],'white');assert.equal(g.captures.black,0);
});
test('positional superko survives undo and a legal ko threat permits recapture',()=>{
 const g=new GameRules('go',9);
 for(const [r,c] of [[0,2],[0,1],[1,1],[1,0],[8,8],[0,3],[0,0]])g.play(r,c);
 assert.throws(()=>g.play(0,1),/劫争/);
 g.play(8,7);g.play(7,8);g.play(0,1);
 assert.equal(g.captures.white,1);g.undo(3);
 assert.throws(()=>g.play(0,1),/劫争/);
});
test('Go pass, shared dead group, resume, score and undo semantics',()=>{
 const g=new GameRules('go',9);g.play(0,0);g.play(8,8);g.play(0,1);
 g.pass();g.pass();assert.equal(g.scoring,true);
 g.toggleDead(0,0);assert.equal(g.dead.size,2);
 assert.deepEqual(g.score(),{black:0,white:88.5});
 g.resume();assert.equal(g.dead.size,0);assert.equal(g.passes,0);
 g.undo(2);assert.equal(g.scoring,false);assert.equal(g.currentPlayer,'white');
});
test('Gomoku five-in-row, board dimensions, strict move bounds and turns',()=>{
 const g=new GameRules('gomoku',15);
 for(let c=0;c<5;c++){g.play(4,c);if(c<4)g.play(5,c);}
 assert.equal(g.winner,'black');assert.throws(()=>g.play(0,0));
 for(const size of [9,13,19]){
  const go=new GameRules('go',size);assert.equal(go.board.length,size);
  assert.throws(()=>go.play(-1,0));assert.throws(()=>go.play(0.5,0));assert.throws(()=>go.play(size,0));
 }
 assert.throws(()=>new GameRules('go',15));assert.throws(()=>new GameRules('chess',9));
});
