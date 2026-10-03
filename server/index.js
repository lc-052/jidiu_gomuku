/**
 * 寄丢五子棋 - WebSocket 联机对战服务器
 * Gomoku Online Multiplayer Server
 *
 * 运行环境：Node.js >= 18
 * 端口：3000
 *
 * 协议（与 lib/services/network_service.dart 严格对齐）：
 *   客户端 → 服务器: register{name} / createRoom{roomName,playerColor} /
 *     joinRoom{roomId} / startGame / makeMove{row,col} / resign /
 *     chat{message} / undoRequest / undoReply{accept} / leaveRoom
 *   服务器 → 客户端: registered / roomCreated{roomId,roomName,yourColor} /
 *     roomJoined{roomId,yourColor,opponentName} / opponentJoined{name,color} /
 *     playerReady{name,color} / gameStarted{black,white,yourColor,yourTurn} /
 *     move{row,col,playerColor,placedBy,nextPlayer} /
 *     gameOver{winner,winnerColor,reason} / chatMessage{message,sender} /
 *     undoAsk{name} / undoAnswer{accept,reason} /
 *     undone{removed:[{row,col}],nextPlayer} / undoCancelled /
 *     errorMsg{message,sender} / opponentLeft{name} / opponentDisconnected{name}
 */

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const expressApp = express();
expressApp.use(cors());
expressApp.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

const server = http.createServer(expressApp);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  pingTimeout: 60000,
  pingInterval: 25000,
});

// ==================== Room State ====================
// rooms: Map<roomId, { name, players[], board, currentPlayer, gameState }>
const rooms = new Map();

// players: Map<socketId, { name, roomId, color, ready }>
const players = new Map();

const BOARD_SIZE = 15;

function emptyBoard() {
  return Array.from({ length: BOARD_SIZE }, () => Array(BOARD_SIZE).fill(null));
}

// ==================== Event Handlers ====================

io.on('connection', (socket) => {
  console.log(`[INFO] Client connected: ${socket.id}`);

  // 注册玩家
  socket.on('register', ({ name }) => {
    let playerName = (name || '').trim();
    // “玩家”是客户端的默认占位名：双方同名会互相误挡对方的聊天消息，
    // 这里给占位名加上 socket 后缀保证可区分
    if (playerName === '' || playerName === '玩家') {
      playerName = `玩家${socket.id.slice(0, 4)}`;
    }
    players.set(socket.id, { name: playerName, roomId: null, color: null, ready: false });
    socket.emit('registered', { name: playerName, playerId: socket.id.slice(0, 8) });
  });

  // 创建房间
  socket.on('createRoom', ({ roomName, playerColor }) => {
    const player = players.get(socket.id);
    if (!player) {
      socket.emit('errorMsg', { message: '请先注册', sender: '系统' });
      return;
    }

    // 6 位数字房间码（100000–999999），与现有房间冲突则重取
    let roomId;
    do {
      roomId = String(Math.floor(100000 + Math.random() * 900000));
    } while (rooms.has(roomId));
    const color = (playerColor || 'black').toLowerCase() === 'white' ? 'white' : 'black';

    const room = {
      id: roomId,
      name: (roomName || '').trim() || `对局 #${roomId}`,
      players: [
        { socketId: socket.id, name: player.name, color: color },
      ],
      board: emptyBoard(),
      currentPlayer: 'black',
      gameState: 'waiting', // waiting | playing | finished
      history: [], // 本局落子记录 [{row,col,color}]，悔棋依据
      pendingUndo: null, // 待答复的悔棋请求 {by,to,moves,historyLen}
      createdAt: Date.now(),
    };

    rooms.set(roomId, room);
    player.roomId = roomId;
    player.color = color;

    socket.join(roomId);
    socket.emit('roomCreated', { roomId, roomName: room.name, yourColor: color });

    console.log(`[ROOM] Created "${room.name}" (${roomId}) by ${player.name} [${color}]`);
  });

  // 加入房间（支持按房间 ID 或房间名称查找）
  socket.on('joinRoom', ({ roomId }) => {
    const player = players.get(socket.id);
    if (!player) {
      socket.emit('errorMsg', { message: '请先注册', sender: '系统' });
      return;
    }

    // 如果已在其他房间，先按离开处理，避免旧房间残留幽灵玩家
    if (player.roomId && rooms.has(player.roomId)) handleLeave(socket.id);

    let room = rooms.get(roomId);
    if (!room) {
      room = [...rooms.values()].find(r => r.name === roomId);
    }
    if (!room) {
      socket.emit('errorMsg', { message: '房间不存在', sender: '系统' });
      return;
    }

    if (room.players.length >= 2) {
      socket.emit('errorMsg', { message: '房间已满', sender: '系统' });
      return;
    }

    if (room.gameState !== 'waiting') {
      socket.emit('errorMsg', { message: '游戏已开始，无法加入', sender: '系统' });
      return;
    }

    const color = room.players[0].color === 'black' ? 'white' : 'black';
    room.players.push({ socketId: socket.id, name: player.name, color: color });

    player.roomId = room.id;
    player.color = color;

    socket.join(room.id);

    const opponent = room.players.find(p => p.socketId !== socket.id);

    // 向加入者确认（携带房间信息与对手昵称，客户端据此导航）
    socket.emit('roomJoined', {
      roomId: room.id,
      yourColor: color,
      opponentName: opponent ? opponent.name : '对手',
    });

    // 向房间内既有玩家定向通知对手加入
    if (opponent) {
      io.to(opponent.socketId).emit('opponentJoined', { name: player.name, color: color });
    }

    console.log(`[ROOM] ${player.name} joined "${room.name}" [${color}]`);
  });

  // 开始游戏（双方都按下准备后自动开局）
  socket.on('startGame', () => {
    const player = players.get(socket.id);
    if (!player) return;
    if (!player.roomId || !rooms.has(player.roomId)) {
      socket.emit('errorMsg', { message: '房间已不存在，请返回大厅重新创建或加入', sender: '系统' });
      return;
    }

    const room = rooms.get(player.roomId);
    if (room.gameState === 'playing') return;
    if (room.players.length < 2) {
      socket.emit('errorMsg', { message: '等待对手进入房间', sender: '系统' });
      return;
    }

    // 对局结束后双方在本页再按准备 → 重置棋盘，等待重新凑齐双方准备
    if (room.gameState === 'finished') {
      room.gameState = 'waiting';
      room.board = emptyBoard();
      room.currentPlayer = 'black';
      room.history = [];
      room.pendingUndo = null;
      room.players.forEach((p) => {
        const pl = players.get(p.socketId);
        if (pl) pl.ready = false;
      });
    }

    player.ready = true;

    const opponentEntry = room.players.find(p => p.socketId !== socket.id);
    const opponent = opponentEntry ? players.get(opponentEntry.socketId) : null;

    if (opponent) {
      // 只通知对方“谁准备了”
      io.to(opponentEntry.socketId).emit('playerReady', { name: player.name, color: player.color });
    }

    if (player.ready && opponent && opponent.ready) {
      startRoom(room);
    }
  });

  // 落子
  socket.on('makeMove', ({ row, col }) => {
    const player = players.get(socket.id);
    if (!player || !player.roomId) return;

    const room = rooms.get(player.roomId);
    if (!room || room.gameState !== 'playing') return;

    const r = Number(row), c = Number(col);
    if (!Number.isInteger(r) || !Number.isInteger(c)) return;
    if (r < 0 || r >= BOARD_SIZE || c < 0 || c >= BOARD_SIZE) return;
    if (room.currentPlayer !== player.color) {
      socket.emit('errorMsg', { message: '现在不是你的回合', sender: '系统' });
      return;
    }
    if (room.board[r][c] !== null) return;

    // Place stone
    room.board[r][c] = player.color;
    room.history.push({ row: r, col: c, color: player.color });
    room.currentPlayer = player.color === 'black' ? 'white' : 'black';

    // Broadcast move to both players (client ignores its own echo)
    io.to(room.id).emit('move', {
      row: r, col: c,
      playerColor: player.color,
      placedBy: player.name,
      nextPlayer: room.currentPlayer,
    });

    // Check win
    if (checkWin(room, r, c)) {
      finishRoom(room, {
        winner: player.name,
        winnerColor: player.color,
        reason: 'five-in-a-row',
      });
      console.log(`[WIN] ${player.name} won in "${room.name}"`);
    } else if (isBoardFull(room)) {
      finishRoom(room, { winner: null, winnerColor: null, reason: 'draw' });
      console.log(`[DRAW] Draw in "${room.name}"`);
    }
  });

  // 投降
  socket.on('resign', () => {
    const player = players.get(socket.id);
    if (!player || !player.roomId) return;

    const room = rooms.get(player.roomId);
    if (!room || room.gameState !== 'playing') return;

    const opponent = room.players.find(p => p.socketId !== socket.id);

    finishRoom(room, {
      winner: opponent ? opponent.name : null,
      winnerColor: opponent ? opponent.color : player.color === 'black' ? 'white' : 'black',
      reason: 'resign',
      resignedBy: player.name,
    });

    console.log(`[RESIGN] ${player.name} resigned in "${room.name}"`);
  });

  // 聊天消息：只广播给房间里的其他人（不回显给发送者，
  // 客户端发送时已把消息本地插入聊天记录）
  socket.on('chat', ({ message }) => {
    const player = players.get(socket.id);
    if (!player || !message || !player.roomId) return;

    socket.broadcast.to(player.roomId).emit('chatMessage', {
      message: String(message).substring(0, 100),
      sender: player.name,
    });
  });

  // 悔棋请求（需对方同意）：若对方已应子则撤两步（应子+自己一步），否则撤自己一步
  socket.on('undoRequest', () => {
    const player = players.get(socket.id);
    if (!player || !player.roomId) return;
    const room = rooms.get(player.roomId);
    if (!room || room.gameState !== 'playing') {
      socket.emit('undoAnswer', { accept: false, reason: 'not-playing' });
      return;
    }
    if (room.pendingUndo) {
      socket.emit('undoAnswer', { accept: false, reason: 'busy' });
      return;
    }
    const h = room.history;
    let moves = 0;
    if (h.length >= 2 && h[h.length - 1].color !== player.color && h[h.length - 2].color === player.color) {
      moves = 2; // 自己一步 + 对方应子一步
    } else if (h.length >= 1 && h[h.length - 1].color === player.color) {
      moves = 1; // 仅自己最后一步（对方尚未应子）
    }
    if (moves === 0) {
      socket.emit('undoAnswer', { accept: false, reason: 'no-move' });
      return;
    }
    const opponent = room.players.find((p) => p.socketId !== socket.id);
    if (!opponent) {
      socket.emit('undoAnswer', { accept: false, reason: 'no-opponent' });
      return;
    }
    room.pendingUndo = { by: socket.id, to: opponent.socketId, moves, historyLen: h.length };
    io.to(opponent.socketId).emit('undoAsk', { name: player.name });
    console.log(`[UNDO] ${player.name} requests undo (${moves} ply)`);
  });

  // 悔棋答复：只有被请求方的一次答复有效
  socket.on('undoReply', ({ accept }) => {
    const player = players.get(socket.id);
    if (!player || !player.roomId) return;
    const room = rooms.get(player.roomId);
    const pu = room && room.pendingUndo;
    if (!pu || pu.to !== socket.id) return; // 过期答复，忽略
    room.pendingUndo = null;

    if (!accept) {
      io.to(pu.by).emit('undoAnswer', { accept: false, reason: 'rejected' });
      return;
    }
    const h = room.history;
    // 询问期间棋局发生了变化（对方抢先落子/终局）→ 悔棋作废
    if (room.gameState !== 'playing' || h.length !== pu.historyLen) {
      io.to(pu.by).emit('undoAnswer', { accept: false, reason: 'stale' });
      return;
    }
    const removed = h.splice(h.length - pu.moves, pu.moves);
    for (const m of removed) room.board[m.row][m.col] = null;
    const requester = players.get(pu.by);
    if (requester && requester.color) room.currentPlayer = requester.color;
    io.to(room.id).emit('undone', {
      removed: removed.map((m) => ({ row: m.row, col: m.col })),
      nextPlayer: room.currentPlayer,
    });
    console.log(`[UNDO] ${requester ? requester.name : pu.by} undid ${pu.moves} ply in "${room.name}"`);
  });

  // 离开房间
  socket.on('leaveRoom', () => {
    handleLeave(socket.id);
  });

  // 断线处理
  socket.on('disconnect', () => {
    handleDisconnect(socket.id);
  });
});

// ==================== Helper Functions ====================

function startRoom(room) {
  room.gameState = 'playing';
  room.currentPlayer = 'black';
  room.board = emptyBoard();
  room.history = [];
  room.pendingUndo = null;

  // 重置准备标记，为下一局准备
  room.players.forEach(p => {
    const pl = players.get(p.socketId);
    if (pl) pl.ready = false;
  });

  // gameStarted 必须逐人定向发送（yourColor / yourTurn 因人而异）
  room.players.forEach(p => {
    io.to(p.socketId).emit('gameStarted', {
      black: room.players.find(x => x.color === 'black')?.name,
      white: room.players.find(x => x.color === 'white')?.name,
      yourColor: p.color,
      yourTurn: p.color === 'black',
    });
  });

  console.log(`[GAME] Started in "${room.name}"`);
}

function finishRoom(room, result) {
  room.gameState = 'finished';
  io.to(room.id).emit('gameOver', result);
}

function notifySurvivor(room, leftName, reason) {
  // 只剩一人时：进行中的对局判留守方胜；等待中则仅提示对手离开
  if (room.gameState === 'playing') {
    const survivor = room.players[0];
    io.to(room.id).emit('gameOver', {
      winner: survivor ? survivor.name : null,
      winnerColor: survivor ? survivor.color : null,
      reason: reason,
      leftBy: leftName,
    });
  } else if (room.gameState === 'waiting') {
    const survivor = room.players[0];
    if (survivor) {
      io.to(survivor.socketId).emit(
        reason === 'disconnected' ? 'opponentDisconnected' : 'opponentLeft',
        { name: leftName },
      );
    }
  }
  room.gameState = 'finished';
  // 房间即将销毁：清掉留守方的服务器端房间状态，
  // 防止陈旧 roomId 阻碍其后续建房/加房
  const survivorPlayer = room.players[0] ? players.get(room.players[0].socketId) : null;
  if (survivorPlayer) {
    survivorPlayer.roomId = null;
    survivorPlayer.ready = false;
  }
  rooms.delete(room.id);
}

// 撤销与相关方离开/掉线时的挂起悔棋清理
function cancelPendingUndo(room, cancellingSocketId) {
  const pu = room.pendingUndo;
  if (!pu) return;
  room.pendingUndo = null;
  if (pu.by === cancellingSocketId) {
    io.to(pu.to).emit('undoCancelled');
  } else {
    io.to(pu.by).emit('undoAnswer', { accept: false, reason: 'left' });
  }
}

function handleDisconnect(socketId) {
  console.log(`[DISCONNECT] ${socketId}`);
  const player = players.get(socketId);
  if (!player) return;

  if (player.roomId && rooms.has(player.roomId)) {
    const room = rooms.get(player.roomId);
    cancelPendingUndo(room, socketId);
    const idx = room.players.findIndex(p => p.socketId === socketId);

    if (idx >= 0) {
      room.players.splice(idx, 1);
      console.log(`[INFO] ${player.name} disconnected from "${room.name}"`);

      if (room.players.length < 2) {
        notifySurvivor(room, player.name, 'disconnected');
      }
    }
  }

  players.delete(socketId);
}

function handleLeave(socketId) {
  const player = players.get(socketId);
  if (!player) return;

  if (player.roomId && rooms.has(player.roomId)) {
    const room = rooms.get(player.roomId);
    cancelPendingUndo(room, socketId);
    const idx = room.players.findIndex(p => p.socketId === socketId);

    if (idx >= 0) {
      const leavingSocket = io.sockets.sockets.get(socketId);
      if (leavingSocket) leavingSocket.leave(room.id);

      room.players.splice(idx, 1);
      console.log(`[LEAVE] ${player.name} left "${room.name}"`);

      if (room.players.length < 2) {
        notifySurvivor(room, player.name, 'left');
      }
    }
  }

  player.roomId = null;
  player.color = null;
  player.ready = false;
}

function checkWin(room, row, col) {
  const stone = room.board[row][col];
  if (!stone) return false;

  const directions = [
    [0, 1],   // horizontal
    [1, 0],   // vertical
    [1, 1],   // diagonal down-right
    [1, -1],  // diagonal down-left
  ];

  for (const [dr, dc] of directions) {
    let count = 1;

    // Count in positive direction
    for (let i = 1; i < 5; i++) {
      const r = row + dr * i;
      const c = col + dc * i;
      if (r >= 0 && r < BOARD_SIZE && c >= 0 && c < BOARD_SIZE && room.board[r][c] === stone) {
        count++;
      } else break;
    }

    // Count in negative direction
    for (let i = 1; i < 5; i++) {
      const r = row - dr * i;
      const c = col - dc * i;
      if (r >= 0 && r < BOARD_SIZE && c >= 0 && c < BOARD_SIZE && room.board[r][c] === stone) {
        count++;
      } else break;
    }

    if (count >= 5) return true;
  }

  return false;
}

function isBoardFull(room) {
  for (let r = 0; r < BOARD_SIZE; r++) {
    for (let c = 0; c < BOARD_SIZE; c++) {
      if (room.board[r][c] === null) return false;
    }
  }
  return true;
}

// ==================== Start Server ====================

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`========================================`);
  console.log(`  寄丢五子棋 联机服务器启动成功!`);
  console.log(`  地址: ws://0.0.0.0:${PORT}`);
  console.log(`  健康检查: http://0.0.0.0:${PORT}/health`);
  console.log(`========================================`);
});

// Graceful shutdown（PM2 stop 默认发 SIGINT，须与 SIGTERM 一并处理）
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log(`\n[SHUTDOWN] ${sig} received, shutting down...`);
    server.close(() => process.exit(0));
  });
}
