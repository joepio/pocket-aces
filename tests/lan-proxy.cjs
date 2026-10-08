// Optional Windows LAN bridge for a WSL-only disposable companion test.
// node tests/lan-proxy.cjs [listen-port=18114] [upstream-port=18113]
// Stop this process when the test is over. No accounts or files are stored here.
const http = require('node:http');
const net = require('node:net');
const listen = Number(process.argv[2] || 18114);
const target = Number(process.argv[3] || 18113);
const server = http.createServer((req,res) => {
  const upstream = http.request({host:'127.0.0.1',port:target,path:req.url,method:req.method,headers:req.headers}, response => {
    res.writeHead(response.statusCode,response.headers); response.pipe(res);
  });
  upstream.on('error',()=>{res.writeHead(502);res.end('The disposable poker test is not running.');});
  req.pipe(upstream);
});
server.on('upgrade',(req,socket,head)=>{
  const upstream=net.connect(target,'127.0.0.1',()=>{
    upstream.write(`${req.method} ${req.url} HTTP/1.1\r\n${Object.entries(req.headers).map(([k,v])=>`${k}: ${v}`).join('\r\n')}\r\n\r\n`);
    if(head.length) upstream.write(head);
    upstream.pipe(socket);socket.pipe(upstream);
  });
  upstream.on('error',()=>socket.destroy());socket.on('error',()=>upstream.destroy());
  socket.on('close',()=>upstream.destroy());upstream.on('close',()=>socket.destroy());
});
server.listen(listen,'0.0.0.0',()=>console.log(`Disposable poker companion bridge listening on ${listen}`));
