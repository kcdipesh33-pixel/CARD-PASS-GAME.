import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:qr_flutter/qr_flutter.dart';

const hostPin=String.fromEnvironment('HOST_PIN',defaultValue:'7777');
void main()=>runApp(const MaterialApp(debugShowCheckedModeBanner:false,themeMode:ThemeMode.dark,home:Home()));
class C {
 final String id,rank,suit; final bool joker;
 C(this.id,this.rank,this.suit,[this.joker=false]);
 Map<String,dynamic> j()=>{'id':id,'rank':rank,'suit':suit,'joker':joker};
 factory C.from(Map m)=>C(m['id'],m['rank'],m['suit'],m['joker']==true);
 String get label=>joker?'JOKER':'$rank$suit';
}
List<C> deck(){
 const suits=['♠','♥','♦','♣'], ranks=['A','2','3','4','5','6','7','8','9','10','J','Q','K'];
 final a=<C>[]; for(final s in suits){for(final r in ranks){a.add(C('$r$s','$r',s));}}
 for(int i=1;i<=4;i++){a.add(C('JOKER$i','JOKER','$i',true));}
 a.shuffle(Random.secure());return a;
}
const bg=Color(0xff101020), purple=Color(0xff7657e8), green=Color(0xff169c55);

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style, size: 80, color: purple),
              const SizedBox(height: 16),
              const Text(
                'CARD PASS',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text('PLAY • PASS • WIN'),
              const SizedBox(height: 30),
              SizedBox(
                width: 240,
                child: FilledButton(
                  onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute(builder: (_) => const Host()),
                  ),
                  child: const Text('HOST'),
                ),
              ),
              SizedBox(
                width: 240,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute(builder: (_) => const Player()),
                  ),
                  child: const Text('PLAYER'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Host extends StatefulWidget{const Host({super.key});@override State<Host> createState()=>_HostState();}
class _HostState extends State<Host>{
 final pin=TextEditingController(); bool ok=false,started=false,ended=false; HttpServer? server;String ip='',msg='Owner PIN';
 int limit=8; final Map<String,String> names={};final Map<String,WebSocket> ws={};
 final Map<String,List<C>> hands={};final Map<String,Set<String>> passed={};final List<C> store=[];
 final List<String> alerts=[];final List<int> history=[];final Set<String> finishedThisTurn={};
 int? goti;
 Future<String> getIp()async{try{for(final n in await NetworkInterface.list(type:InternetAddressType.IPv4,includeLoopback:false)){for(final a in n.addresses){if(!a.isLoopback&&!a.address.startsWith('169.254.'))return a.address;}}}catch(_){}return 'IP unavailable';}
 void send(String id,Map m){final s=ws[id];if(s!=null&&s.readyState==WebSocket.open)s.add(jsonEncode(m));}
 void pub(){final m=jsonEncode({'type':'state','names':names.values.toList(),'goti':goti,'ended':ended});for(final s in ws.values){if(s.readyState==WebSocket.open)s.add(m);}}
 void priv(String id)=>send(id,{'type':'hand','cards':(hands[id]??[]).map((c)=>c.j()).toList(),'passed':(passed[id]??{}).toList()});
 Future<void> startServer()async{
 try{server=await HttpServer.bind(InternetAddress.anyIPv4,8080);ip=await getIp();server!.listen((r)async{
 if(!WebSocketTransformer.isUpgradeRequest(r)){r.response..write('CARD PASS')..close();return;}
 final s=await WebSocketTransformer.upgrade(r);String? id;
 s.listen((raw){try{final m=jsonDecode(raw as String);
 if(m['type']=='join'){if(started||names.length>=limit){s.add(jsonEncode({'type':'error','msg':'Lobby closed/full'}));s.close();return;}
 id='${DateTime.now().microsecondsSinceEpoch}';names[id!]=(m['name']??'Player').toString();ws[id!]=s;priv(id!);pub();setState((){});}
 else if(id!=null&&m['type']=='pass'){passCards(id!,m);}
 }catch(_){}},onDone:(){if(id!=null){names.remove(id);ws.remove(id);hands.remove(id);passed.remove(id);pub();setState((){});}});
 });setState(()=>msg='Host running');}catch(e){setState(()=>msg='Host error: $e');}}
 void deal(){if(names.length<2)return;final d=deck();hands.clear();passed.clear();store.clear();alerts.clear();history.clear();finishedThisTurn.clear();for(final id in names.keys){final h=d.take(7).toList();hands[id]=h;passed[id]=h.where((c)=>c.joker).map((c)=>c.id).toSet();priv(id);}started=true;ended=false;goti=null;pub();setState((){});}
 void choose(int n){if(!started||ended)return;history.add(n);goti=n;finishedThisTurn.clear();pub();setState((){});}
 void undo(){if(history.isEmpty)return;history.removeLast();goti=history.isEmpty?null:history.last;pub();setState((){});}
 void passCards(String id,Map m){if(goti==null||ended)return;final selected=(m['cards'] as List).cast<String>().toSet();final h=hands[id]??[];final eligible=h.where((c)=>!c.joker&&!(passed[id]??{}).contains(c.id)&&c.rank==goti.toString()).map((c)=>c.id).toSet();
 if(selected.isEmpty)return;if(!selected.containsAll(eligible)||selected.length!=eligible.length){alerts.add(id);send(id,{'type':'wrong'});setState((){});return;}
 passed[id]!.addAll(selected);final reveal=m['reveal'];if(reveal!=null&&selected.contains(reveal)){for(final s in ws.values){s.add(jsonEncode({'type':'reveal','card':reveal,'name':names[id]}));}Future.delayed(const Duration(seconds:5),(){for(final s in ws.values){if(s.readyState==WebSocket.open)s.add(jsonEncode({'type':'hide'}));}});}
 if(passed[id]!.length==7)finishedThisTurn.add(id);priv(id);pub();setState((){});}
 void kick(String id){store.addAll((hands[id]??[]).where((c)=>!(passed[id]??{}).contains(c.id)));send(id,{'type':'kicked'});ws[id]?.close();ws.remove(id);names.remove(id);hands.remove(id);passed.remove(id);finishedThisTurn.remove(id);pub();setState((){});}
 void winner(String id){if(finishedThisTurn.length!=1||!finishedThisTurn.contains(id))return;ended=true;for(final s in ws.values){s.add(jsonEncode({'type':'winner','name':names[id]}));}pub();setState((){});}
 void cancel(){ended=true;for(final s in ws.values){s.add(jsonEncode({'type':'cancelled'}));}pub();setState((){});}
 @override void dispose(){server?.close(force:true);for(final s in ws.values){s.close();}pin.dispose();super.dispose();}
 @override Widget build(BuildContext c){
 if(!ok)return Scaffold(backgroundColor:bg,appBar:AppBar(title:const Text('Host PIN')),body:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[TextField(controller:pin,obscureText:true,decoration:const InputDecoration(labelText:'Owner PIN')),FilledButton(onPressed:(){setState(()=>ok=pin.text==hostPin);if(!ok)setState(()=>msg='Wrong PIN');},child:const Text('UNLOCK')),Text(msg)])));
 return Scaffold(backgroundColor:bg,appBar:AppBar(title:const Text('HOST CONTROL')),body:ListView(padding:const EdgeInsets.all(14),children:[
 Text(msg),if(server==null)FilledButton(onPressed:startServer,child:const Text('START HOST SERVER')),
 if(ip.isNotEmpty)...[SelectableText('Host IP: $ip:8080'),QrImageView(data:'$ip:8080',size:130,backgroundColor:Colors.white)],
 DropdownButton<int>(value:limit,items:[2,3,4,5,6,7,8].map((n)=>DropdownMenuItem(value:n,child:Text('$n Players'))).toList(),onChanged:started?null:(v)=>setState(()=>limit=v!)),
 Text('Players ${names.length}/$limit'),for(final e in names.entries)ListTile(title:Text(e.value),trailing:TextButton(onPressed:()=>kick(e.key),child:const Text('KICK'))),
 if(!started)FilledButton(onPressed:names.length>=2?deal:null,child:const Text('DISTRIBUTE CARDS')),
 if(started&&!ended)Wrap(children:[for(int n=1;n<=13;n++)Padding(padding:const EdgeInsets.all(3),child:FilledButton(onPressed:()=>choose(n),child:Text('$n')))]),
 if(started&&!ended)OutlinedButton(onPressed:undo,child:const Text('UNDO')),
 const Text('HOST CARD VIEW'),for(final e in hands.entries)ExpansionTile(title:Text('${names[e.key]??'Player'} (${passed[e.key]?.length??0}/7)'),children:[Wrap(children:[for(final c in e.value)Padding(padding:const EdgeInsets.all(3),child:Chip(backgroundColor:passed[e.key]!.contains(c.id)?green:Colors.blueGrey,label:Text(c.label)))])]),
 if(alerts.isNotEmpty)const Text('WRONG CARD ALERTS',style:TextStyle(color:Colors.orange)),for(final id in alerts.toSet())ListTile(title:Text('Wrong card: ${names[id]??'Player'}'),trailing:Wrap(children:[TextButton(onPressed:()=>setState(()=>alerts.remove(id)),child:const Text('IGNORE')),TextButton(onPressed:()=>kick(id),child:const Text('KICK'))])),
 if(finishedThisTurn.length==1)FilledButton(onPressed:()=>winner(finishedThisTurn.first),child:const Text('WINNER')),
 if(finishedThisTurn.length>1)FilledButton(onPressed:cancel,child:const Text('CANCEL')),
 if(ended)FilledButton(onPressed:deal,child:const Text('NEW GAME')),Text('Stored cards: ${store.length}')
 ]));}
}
class Player extends StatefulWidget{const Player({super.key});@override State<Player> createState()=>_PlayerState();}
class _PlayerState extends State<Player>{
 final ip=TextEditingController(),name=TextEditingController();IOWebSocketChannel? ch;bool connected=false,kicked=false;String status='Enter name and Host IP';List<C> cards=[];Set<String> passed={},selected={};int? goti;String? reveal;bool ended=false;
 void join(){try{ch=IOWebSocketChannel.connect(Uri.parse('ws://${ip.text.trim()}:8080'));ch!.stream.listen((raw){final m=jsonDecode(raw.toString());setState((){
 switch(m['type']){
 case 'hand':cards=(m['cards'] as List).map((e)=>C.from(e)).toList();passed=(m['passed'] as List).cast<String>().toSet();connected=true;status='Connected';break;
 case 'state':goti=m['goti'];ended=m['ended']==true;break;
 case 'reveal':reveal='${m['name']}: ${m['card']}';break;case 'hide':reveal=null;break;
 case 'wrong':status='Wrong card. Host alerted.';break;case 'kicked':kicked=true;connected=false;status='Kicked by Host';break;
 case 'winner':status='Winner: ${m['name']}';ended=true;break;case 'cancelled':status='Game cancelled';ended=true;break;case 'error':status=m['msg'];break;
 }});},onError:(_)=>setState(()=>status='Connection failed'),onDone:()=>setState(()=>connected=false));ch!.sink.add(jsonEncode({'type':'join','name':name.text.trim()}));}catch(_){setState(()=>status='Connection failed');}}
 void submit(){final needed=cards.where((c)=>!c.joker&&!passed.contains(c.id)&&c.rank==goti.toString()).map((c)=>c.id).toSet();if(needed.isEmpty){setState(()=>status='No matching card');return;}if(!selected.containsAll(needed)){setState(()=>status='Select all matching cards');return;}ch!.sink.add(jsonEncode({'type':'pass','cards':needed.toList(),'reveal':selected.intersection(needed).firstOrNull}));setState(()=>status='Sent to host');}
 @override void dispose(){ch?.sink.close();ip.dispose();name.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(backgroundColor:bg,appBar:AppBar(title:const Text('PLAYER')),body:ListView(padding:const EdgeInsets.all(16),children:[
 if(!connected)...[TextField(controller:name,decoration:const InputDecoration(labelText:'Player name')),TextField(controller:ip,decoration:const InputDecoration(labelText:'Host IP'),keyboardType:TextInputType.url),FilledButton(onPressed:join,child:const Text('JOIN'))],
 Text(status),if(reveal!=null)Container(color:Colors.amber,padding:const EdgeInsets.all(10),child:Text(reveal!,style:const TextStyle(color:Colors.black))),
 if(connected)...[Text('Goti: ${goti??'-'}',style:const TextStyle(fontSize:24)),Wrap(spacing:8,runSpacing:8,children:[for(final x in cards)InkWell(onTap:()=>setState(()=>selected.contains(x.id)?selected.remove(x.id):selected.add(x.id)),child:Container(width:72,height:96,decoration:BoxDecoration(color:passed.contains(x.id)?green:const Color(0xff292943),border:Border.all(color:selected.contains(x.id)?Colors.yellow:Colors.white24,width:2),borderRadius:BorderRadius.circular(9)),child:Center(child:Text(x.label,style:TextStyle(fontSize:17,color:['♥','♦'].contains(x.suit)?Colors.red:Colors.white))))) ]),FilledButton(onPressed:submit,child:const Text('GREEN CHECK ✓')),const Text('Jokers are automatically passed and shown green.')],
 ]));
}
