'use strict';
const express=require('express');
const http=require('http');
const path=require('path');
const fs=require('fs');
const {randomInt}=require('crypto');
const {Server}=require('socket.io');
const {GameRules,other}=require('./game_rules');
function createGameServer(options={}) {
  const app=express(),server=http.createServer(app);
  app.get('/health',(_,res)=>res.json({status:'ok',protocol:2,games:['gomoku','go'],uptime:process.uptime()}));
  const webRoot=options.webRoot||process.env.WEB_ROOT||path.join(__dirname,'web');
  if(fs.existsSync(path.join(webRoot,'index.html'))) {
    app.use(express.static(webRoot,{setHeaders(res,file) {
      // Deploy updates immediately instead of retaining an old app entry point.
      if(/\.(html|js|json)$/.test(file)) res.setHeader('Cache-Control','no-cache');
    }}));
    app.get('*',(req,res,next)=>{
      if(req.path.startsWith('/socket.io')||path.extname(req.path)) return next();
      res.sendFile(path.join(webRoot,'index.html'));
    });
  }
  const io=new Server(server,{cors:{origin:'*',methods:['GET','POST']},maxHttpBufferSize:8192,pingTimeout:20000,pingInterval:25000});
  const rooms=new Map(),players=new Map();
  function error(socket,message) {socket.emit('errorMsg',{message,sender:'系统'});}
  function snapshot(room) {
    const g=room.game;
    return {roomId:room.id,roomName:room.name,kind:g.kind,size:g.size,phase:room.phase,
      board:g.board,currentPlayer:g.currentPlayer,passes:g.passes,captures:g.captures,
      moveCount:g.history.length,lastMove:g.lastMove,dead:[...g.dead].map(p=>({row:Math.floor(p/g.size),col:p%g.size})),
      players:room.players.map(id=>{const p=players.get(id);return {name:p.name,color:p.color,ready:p.ready};}),
      confirmations:[...room.confirmations].map(id=>players.get(id)?.color).filter(Boolean),
      score:room.phase==='scoring'||room.result?.reason==='score'?g.score():null,
      winnerColor:room.result?.winnerColor??null,reason:room.result?.reason??null,
      revision:room.revision,undoPending:!!room.pendingUndo};
  }
  function publish(room) {room.revision++;io.to(room.id).emit('state',snapshot(room));}
  function cancelUndo(room,reason='stale') {
    const pending=room.pendingUndo;if(!pending) return;
    clearTimeout(pending.timer);room.pendingUndo=null;
    io.to(pending.by).emit('undoAnswer',{accept:false,reason});
    io.to(pending.to).emit('undoCancelled');
  }
  function finish(room,result) {
    cancelUndo(room);room.phase='finished';room.result=result;
    room.players.forEach(id=>{players.get(id).ready=false;});
    io.to(room.id).emit('gameOver',result);publish(room);
  }
  function leave(socket,disconnected=false) {
    const player=players.get(socket.id);if(!player) return;
    const room=rooms.get(player.roomId);
    if(room) {
      cancelUndo(room,'left');socket.leave(room.id);
      room.players=room.players.filter(id=>id!==socket.id);
      if(room.players.length) {
        const survivor=players.get(room.players[0]);
        if(['playing','scoring'].includes(room.phase)) finish(room,{winner:survivor.name,winnerColor:survivor.color,reason:disconnected?'disconnected':'left'});
        else {io.to(room.id).emit('opponentLeft',{name:player.name});}
        // A departed opponent ends the room. Survivor must return to the lobby.
        io.to(room.id).emit('roomClosed',{message:'对手已离开，请返回大厅重新建房'});
        const survivorSocket=io.sockets.sockets.get(room.players[0]);
        survivorSocket?.leave(room.id);survivor.roomId=null;survivor.ready=false;
      }
      rooms.delete(room.id);
    }
    player.roomId=null;player.color=null;player.ready=false;
  }
  function member(socket) {
    const player=players.get(socket.id),room=player&&rooms.get(player.roomId);
    if(!room) throw Error('当前不在房间中，请返回大厅');
    return {player,room};
  }
  function turn(socket) {
    const state=member(socket);
    if(state.room.phase!=='playing') throw Error('本局当前不能行棋');
    if(state.room.game.currentPlayer!==state.player.color) throw Error('现在不是你的回合');
    return state;
  }
  io.on('connection',socket=>{
    let packets=0,windowStart=Date.now(),lastCreate=0;
    socket.use((packet,next)=>{
      if(Date.now()-windowStart>1000) {packets=0;windowStart=Date.now();}
      if(++packets>50) {error(socket,'操作过于频繁，请稍后再试');return;}
      next();
    });
    function on(event,handler) {
      socket.on(event,(data={})=>{
        try {
          if(!data||typeof data!=='object'||Array.isArray(data)) throw Error('请求数据格式不正确');
          handler(data);
        } catch(e) {error(socket,e.message||'请求失败');}
      });
    }
    on('register',d=>{
      if(players.has(socket.id)) {socket.emit('registered',{name:players.get(socket.id).name,protocol:2});return;}
      if(d.name!==undefined&&typeof d.name!=='string') throw Error('昵称格式不正确');
      const name=(d.name||'').trim().slice(0,24);
      players.set(socket.id,{name:!name||name==='玩家'?'玩家'+socket.id.slice(0,4):name,roomId:null,color:null,ready:false});
      socket.emit('registered',{name:players.get(socket.id).name,protocol:2});
    });
    on('createRoom',d=>{
      const p=players.get(socket.id);if(!p) throw Error('请先连接并注册');
      if(Date.now()-lastCreate<1000) throw Error('请稍后再创建房间');
      if(rooms.size>=1000) throw Error('服务器房间已满');
      if(typeof d.roomName!=='string'||!d.roomName.trim()||d.roomName.length>40) throw Error('请填写有效的房间名称');
      if(d.playerColor!==undefined&&!['black','white'].includes(d.playerColor)) throw Error('执子颜色不正确');
      const game=new GameRules(d.kind??'gomoku',d.size??(d.kind==='go'?9:15));
      leave(socket);lastCreate=Date.now();
      let id;do{id=String(randomInt(100000,1000000));}while(rooms.has(id));
      const room={id,name:d.roomName.trim(),game,players:[socket.id],phase:'waiting',confirmations:new Set(),
        result:null,pendingUndo:null,revision:0};
      rooms.set(id,room);p.roomId=id;p.color=d.playerColor||'black';p.ready=false;socket.join(id);
      socket.emit('roomCreated',{roomId:id,roomName:room.name,yourColor:p.color,kind:game.kind,size:game.size});
      publish(room);
    });
    on('joinRoom',d=>{
      const p=players.get(socket.id);if(!p) throw Error('请先连接并注册');
      if(typeof d.roomId!=='string'||!d.roomId.trim()) throw Error('请填写房间码');
      const room=rooms.get(d.roomId.trim())||[...rooms.values()].find(r=>r.name===d.roomId.trim());
      if(!room) throw Error('房间不存在');
      if(p.roomId===room.id) throw Error('你已在该房间中');
      if(room.players.length>=2) throw Error('房间已满');
      if(room.phase!=='waiting') throw Error('该房间已开始对局');
      if(d.kind && d.kind!==room.game.kind) throw Error('房间玩法不匹配，请切换到对应棋种');
      leave(socket);
      const opponent=players.get(room.players[0]);
      room.players.push(socket.id);p.roomId=room.id;p.color=other(opponent.color);p.ready=false;socket.join(room.id);
      socket.emit('roomJoined',{roomId:room.id,yourColor:p.color,opponentName:opponent.name,kind:room.game.kind,size:room.game.size});
      io.to(room.players[0]).emit('opponentJoined',{name:p.name,color:p.color});publish(room);
    });
    on('startGame',()=>{
      const {player,room}=member(socket);
      if(room.phase==='playing'||room.phase==='scoring') return;
      if(room.players.length!==2) throw Error('等待对手进入房间');
      if(room.phase==='finished') {
        room.game=new GameRules(room.game.kind,room.game.size);room.phase='waiting';room.result=null;room.confirmations.clear();
        room.players.forEach(id=>players.get(id).ready=false);
      }
      player.ready=true;
      socket.to(room.id).emit('playerReady',{name:player.name,color:player.color});
      if(room.players.every(id=>players.get(id).ready)) {
        room.phase='playing';
        for(const id of room.players) {
          const p=players.get(id);
          io.to(id).emit('gameStarted',{yourColor:p.color,yourTurn:p.color==='black',kind:room.game.kind,size:room.game.size});
        }
      }
      publish(room);
    });
    on('makeMove',d=>{
      const {player,room}=turn(socket);room.game.play(d.row,d.col);cancelUndo(room);
      io.to(room.id).emit('move',{row:d.row,col:d.col,playerColor:player.color,nextPlayer:room.game.currentPlayer,placedBy:player.name});
      if(room.game.winner!==undefined) finish(room,{winnerColor:room.game.winner,reason:room.game.winner?'five-in-a-row':'draw'});
      else publish(room);
    });
    on('pass',()=>{
      const {room}=turn(socket);room.game.pass();cancelUndo(room);
      if(room.game.scoring) {room.phase='scoring';room.confirmations.clear();}
      publish(room);
    });
    on('markDead',d=>{
      const {room}=member(socket);
      if(room.phase!=='scoring') throw Error('当前不在终局核对阶段');
      if(d.revision!==room.revision) throw Error('棋局已更新，请核对后重试');
      room.game.toggleDead(d.row,d.col);room.confirmations.clear();publish(room);
    });
    on('confirmScore',d=>{
      const {room}=member(socket);if(room.phase!=='scoring') throw Error('当前不在计分阶段');
      if(d.revision!==room.revision) throw Error('计分已更新，请重新核对');
      room.confirmations.add(socket.id);
      if(room.confirmations.size===2) {
        const score=room.game.score();
        finish(room,{winnerColor:score.black>score.white?'black':score.black<score.white?'white':null,reason:'score',score});
      } else publish(room);
    });
    on('resumePlay',()=>{
      const {room}=member(socket);if(room.phase!=='scoring') throw Error('当前不能恢复对局');
      room.game.resume();room.phase='playing';room.confirmations.clear();publish(room);
    });
    on('resign',()=>{
      const {player,room}=member(socket);if(!['playing','scoring'].includes(room.phase)) throw Error('对局尚未开始或已经结束');
      finish(room,{winnerColor:other(player.color),reason:'resign'});
    });
    on('chat',d=>{
      const {room,player}=member(socket);if(typeof d.message!=='string'||!d.message.trim()) throw Error('消息不能为空');
      socket.to(room.id).emit('chatMessage',{message:d.message.trim().slice(0,100),sender:player.name});
    });
    on('undoRequest',()=>{
      const {room,player}=member(socket);
      if(!['playing','scoring'].includes(room.phase)) throw Error('当前不能悔棋');
      if(room.pendingUndo) throw Error('已有悔棋请求等待答复');
      const h=room.game.history,last=h.at(-1),previous=h.at(-2);
      const count=last?.color===player.color?1:previous?.color===player.color?2:0;
      if(!count) throw Error('暂无你可以撤回的走棋');
      const to=room.players.find(id=>id!==socket.id);
      const pending={by:socket.id,to,count,historyLen:h.length,timer:null};room.pendingUndo=pending;
      pending.timer=setTimeout(()=>{if(room.pendingUndo===pending){cancelUndo(room,'timeout');publish(room);}},30000);
      pending.timer.unref();io.to(to).emit('undoAsk',{name:player.name});publish(room);
    });
    on('undoReply',d=>{
      const {room}=member(socket),pending=room.pendingUndo;
      if(typeof d.accept!=='boolean') throw Error('答复格式不正确');
      if(!pending||pending.to!==socket.id) throw Error('悔棋请求已失效');
      if(!d.accept) {cancelUndo(room,'rejected');publish(room);return;}
      clearTimeout(pending.timer);room.pendingUndo=null;
      if(room.game.history.length!==pending.historyLen) {io.to(pending.by).emit('undoAnswer',{accept:false,reason:'stale'});publish(room);return;}
      const removed=room.game.undo(pending.count);
      room.phase=room.game.scoring?'scoring':'playing';room.confirmations.clear();
      io.to(room.id).emit('undone',{removed:removed.filter(m=>m.type==='move').map(m=>({row:m.row,col:m.col})),nextPlayer:room.game.currentPlayer});
      io.to(pending.by).emit('undoAnswer',{accept:true});publish(room);
    });
    on('getState',()=>{const {room}=member(socket);socket.emit('state',snapshot(room));});
    on('leaveRoom',()=>leave(socket));
    socket.on('disconnect',()=>{leave(socket,true);players.delete(socket.id);});
  });
  return {server,io,rooms};
}
if(require.main===module) {
  const {server,io}=createGameServer();
  const port=Number(process.env.PORT||3000);
  server.listen(port,'0.0.0.0',()=>console.log('READY '+server.address().port));
  for(const sig of ['SIGINT','SIGTERM']) process.once(sig,()=>{
    const timer=setTimeout(()=>process.exit(1),5000);timer.unref();
    io.close(()=>process.exit(0));
  });
}
module.exports={createGameServer};
