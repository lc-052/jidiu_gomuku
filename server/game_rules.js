'use strict';
const other = color => color === 'black' ? 'white' : 'black';
class GameRules {
  constructor(kind = 'gomoku', size = kind === 'go' ? 9 : 15) {
    if (!['gomoku', 'go'].includes(kind) || !(kind === 'go' ? [9,13,19] : [9,15,19]).includes(size)) throw Error('不支持的玩法或棋盘尺寸');
    this.kind = kind; this.size = size;
    this.board = Array.from({length:size},()=>Array(size).fill(null));
    this.currentPlayer = 'black'; this.passes = 0; this.scoring = false;
    this.captures = {black:0,white:0}; this.lastMove = null;
    this.history = []; this.positions = [this.key()]; this.dead = new Set();
    this.winner = undefined; this.komi = 7.5;
  }
  key() { return this.board.map(r=>r.map(v=>v === 'black' ? 'b' : v === 'white' ? 'w' : '.').join('')).join(''); }
  neighbors(i) {
    const n=this.size, list=[];
    if(i>=n) list.push(i-n); if(i<n*(n-1)) list.push(i+n);
    if(i%n>0) list.push(i-1); if(i%n<n-1) list.push(i+1);
    return list;
  }
  cell(i) { return this.board[Math.floor(i/this.size)][i%this.size]; }
  set(i,v) { this.board[Math.floor(i/this.size)][i%this.size]=v; }
  group(start) {
    const color=this.cell(start), stones=new Set([start]), pending=[start], liberties=new Set();
    while(pending.length) {
      for(const q of this.neighbors(pending.pop())) {
        if(this.cell(q) === null) liberties.add(q);
        if(this.cell(q) === color && !stones.has(q)) {stones.add(q);pending.push(q);}
      }
    }
    return {stones,liberties};
  }
  captureState() { return {board:this.board.map(r=>[...r]),currentPlayer:this.currentPlayer,
    passes:this.passes,scoring:this.scoring,captures:{...this.captures},lastMove:this.lastMove,
    positionsLength:this.positions.length,winner:this.winner}; }
  restore(s) {
    this.board=s.board;this.currentPlayer=s.currentPlayer;this.passes=s.passes;
    this.scoring=s.scoring;this.captures=s.captures;this.lastMove=s.lastMove;
    this.positions.length=s.positionsLength;this.winner=s.winner;this.dead.clear();
  }
  play(row,col) {
    if(this.scoring || this.winner !== undefined) throw Error('本局当前不能落子');
    if(!Number.isInteger(row)||!Number.isInteger(col)||row<0||col<0||row>=this.size||col>=this.size||this.board[row][col]!==null) throw Error('请在空交叉点落子');
    const before=this.captureState(), color=this.currentPlayer, pos=row*this.size+col;
    this.board[row][col]=color;
    if(this.kind === 'go') {
      let captured=0;
      for(const q of this.neighbors(pos)) {
        if(this.cell(q)===other(color)) {
          const group=this.group(q);
          if(group.liberties.size===0) {captured+=group.stones.size;for(const p of group.stones) this.set(p,null);}
        }
      }
      if(this.group(pos).liberties.size===0) {this.restore(before);throw Error('禁入点：落子后己方无气');}
      const hash=this.key();
      if(this.positions.includes(hash)) {this.restore(before);throw Error('劫争：不能重复历史局面');}
      this.captures[color]+=captured;this.positions.push(hash);
    } else if(this.checkWin(row,col)) {
      this.winner=color;
    } else if(this.board.every(r=>r.every(Boolean))) {
      this.winner=null;
    }
    this.history.push({before,row,col,color,type:'move'});
    this.lastMove={row,col};this.passes=0;this.currentPlayer=other(color);
  }
  pass() {
    if(this.kind!=='go'||this.scoring||this.winner!==undefined) throw Error('当前不能停着');
    this.history.push({before:this.captureState(),color:this.currentPlayer,type:'pass'});
    this.passes++;this.scoring=this.passes>=2;this.lastMove=null;this.currentPlayer=other(this.currentPlayer);
  }
  undo(count) {
    const removed=[];
    while(count-- >0 && this.history.length) {const entry=this.history.pop();this.restore(entry.before);removed.push(entry);}
    return removed;
  }
  toggleDead(row,col) {
    if(!this.scoring) throw Error('当前不在终局核对阶段');
    if(!Number.isInteger(row)||!Number.isInteger(col)||row<0||col<0||row>=this.size||col>=this.size||!this.board[row][col]) throw Error('请选择棋子');
    const group=this.group(row*this.size+col).stones, remove=this.dead.has(group.values().next().value);
    for(const p of group) {if(remove) this.dead.delete(p);else this.dead.add(p);}
  }
  resume() {this.scoring=false;this.passes=0;this.dead.clear();}
  score() {
    const b=this.board.map(r=>[...r]);
    for(const p of this.dead) b[Math.floor(p/this.size)][p%this.size]=null;
    const cell=p=>b[Math.floor(p/this.size)][p%this.size];
    const totals={black:0,white:this.komi},visited=new Set();
    for(let i=0;i<this.size*this.size;i++) {
      if(cell(i)) {totals[cell(i)]++;continue;}
      if(visited.has(i)) continue;
      const pending=[i],region=new Set([i]),borders=new Set();visited.add(i);
      while(pending.length) for(const q of this.neighbors(pending.pop())) {
        if(cell(q)) borders.add(cell(q));
        else if(!visited.has(q)) {visited.add(q);region.add(q);pending.push(q);}
      }
      if(borders.size===1) totals[borders.values().next().value]+=region.size;
    }
    return totals;
  }
  checkWin(r,c) {
    for(const [dr,dc] of [[0,1],[1,0],[1,1],[1,-1]]) {
      let count=1;
      for(const sign of [-1,1]) {
        let rr=r+dr*sign,cc=c+dc*sign;
        while(rr>=0&&cc>=0&&rr<this.size&&cc<this.size&&this.board[rr][cc]===this.board[r][c]) {count++;rr+=dr*sign;cc+=dc*sign;}
      }
      if(count>=5) return true;
    }
    return false;
  }
}
module.exports={GameRules,other};
