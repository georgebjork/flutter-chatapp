import 'dart:async';
import 'package:chat_app/components/avatar.dart';
import 'package:chat_app/models/Message.dart';
import 'package:chat_app/models/room_page_provider.dart';
import 'package:chat_app/models/profile.dart';
import 'package:chat_app/models/room.dart';
import 'package:chat_app/screens/chat_page.dart';
import 'package:chat_app/screens/register_page.dart';
import 'package:chat_app/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RoomsPage extends StatefulWidget {
  const RoomsPage({ Key? key }) : super(key: key);

  @override
  State<RoomsPage> createState() => _RoomsPageState();

  static Route<void> route() {
    return MaterialPageRoute(builder: (context) => const RoomsPage());
  }
}

class _RoomsPageState extends State<RoomsPage> {

  //List of available profiles to message
  List<Profile> currentProfileData = [];

  // List of rooms you are a part of
  List<Room> currentRoomData = [];

  // The Current User Id
  final String userId = supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
  }

  // This will load all of the available profiles to message 
  Future<void> loadProfiles () async {
    // Grab all profiles 
    final List<dynamic> data = await supabase.from('profiles').select();
    currentProfileData = data.map((index) => Profile.fromMap(index)).toList();
  }

  // This will load all of the rooms for user from the database
  Future<void> loadRooms() async {
    // Grab all of the rooms we are a part of, but filter out ourselves. Row Line Security will only allow us to query rooms we are in.
    final List<dynamic> currentRooms = await supabase.from('room_participants').select().neq('profile_id', userId);
    currentRoomData = currentRooms.map((index) => Room.fromRoomParticipants(index)).toList();
  } 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Rooms'), 
        actions: [
          TextButton(
            onPressed: () async {
              await supabase.auth.signOut();
              // ignore: use_build_context_synchronously
              Navigator.of(context).pushAndRemoveUntil(RegisterPage.route(), (route) => false);
            },
            child: const Text('Logout'),
          ),
        ],
      ),

      body: FutureBuilder(
        future: Future.wait([
          loadProfiles(),
          loadRooms(),
        ]),
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {  
          if (snapshot.hasError) {
            return Text("Error: ${snapshot.error}");
          }

          if (!snapshot.hasData) {
            return preloader;
          } 

          // Set the provider data
          Provider.of<RoomPageProvider>(context, listen: false).profiles = currentProfileData;
          Provider.of<RoomPageProvider>(context, listen: false).rooms = currentRoomData;

          return Column(
            children: const [
              Expanded(flex: 1, child: StartChatBar()),
              Expanded(flex: 9, child: DisplayChats())
            ],
          );
        },
      )
    );
  }
}

class StartChatBar extends StatelessWidget {
  const StartChatBar({Key? key,}) : super(key: key);

  Future<String> createRoom(String otherUserId) async {
    final data = await supabase.rpc('create_new_room',
      params: {'other_user_id': otherUserId});
    return data as String;
  }

  @override 
  Widget build(BuildContext context){

    List<Profile>? profiles = Provider.of<RoomPageProvider>(context, listen: false).profiles;
    List<Room>? rooms = Provider.of<RoomPageProvider>(context, listen: false).rooms;
    
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: profiles!.length,
      itemBuilder: (BuildContext context, int index) {  
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Avatar(profile: profiles[index], onPressed: () async {
                  // Get a room id from function 
                  String roomId = await createRoom(profiles[index].id);
                  // If it exists already, then navigate to it
                  if(rooms!.map((e) => e.id).contains(roomId)) { Navigator.of(context).push(ChatPage.route(roomId)); }
                }),

                Text(profiles[index].username,  overflow: TextOverflow.ellipsis, maxLines: 1)
              ],
            ),
          ),
        );
      }
    );
  }
}




class DisplayChats extends StatefulWidget {
  
  const DisplayChats({Key? key}) : super(key: key);

  @override
  State<DisplayChats> createState() => _DisplayChatsState();
}

class _DisplayChatsState extends State<DisplayChats> {

  // Data I need:

  // A stream of all room data. This will notify us of the addition of rooms.  StreamSubscription<List<Map<String, dynamic>>>? roomsStream;
  // A list of all rooms not attached to the stream subscription. This will allow us to change data. List<Room> rooms
  // A stream of all chat messages data. This will notify us about new chats to display on the room cards. final Map<String, StreamSubscription<Message?>> messagesStream = {};

  int timesRendered = 0;
  // Room data
  late Stream<List<Room>> roomsStream;
  List<Room> rooms = [];

  //Message data
  final Map<String, StreamSubscription<Message?>> messagesStream = {};

  // User id
  final String userId = supabase.auth.currentUser!.id;

  void setRoomsListener() {
   
    roomsStream = supabase.from('room_participants').stream(primaryKey: ['room_id', 'profile_id']).neq('profile_id', userId)
    .map((listOfRooms) => listOfRooms.map((room) { 

      // Rooms now has updated data
      rooms = listOfRooms.map((e) => Room.fromRoomParticipants(e)).toList();

      for (final room in rooms) {
        getNewestMessage(roomId: room.id);
      }

      return Room.fromRoomParticipants(room); 
    }).toList()); 



  }

  void getNewestMessage({required roomId}) {
    messagesStream['roomId'] = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at')
        .limit(1)
        .map<Message?>(
          (data) => data.isEmpty
              ? null
              : Message.fromMap(
                  map: data.first,
                  myUserId: userId,
                ),
        )
        .listen((message) {
          // Set the newest message 
          final index = rooms.indexWhere((room) => room.id == roomId);
          rooms[index] = rooms[index].copyWith(lastMessage: message);

          rooms.sort((a, b) {
            // Sort according to the last message
            // Use the room createdAt when last message is not available
            final aTimeStamp = a.lastMessage != null ? a.lastMessage!.createdAt : a.createdAt;
            final bTimeStamp = b.lastMessage != null ? b.lastMessage!.createdAt : b.createdAt;
            return bTimeStamp.compareTo(aTimeStamp);
          });
          setState(() {});
        });
  }

  Profile getProfileName(String id, List<Profile> profiles){
    int index = profiles.indexWhere((element) => element.id == id);
    return profiles[index];
  }

  @override
  void initState() {
    setRoomsListener();
    super.initState();
  }


  @override
  Widget build(BuildContext context) {

    List<Profile>? currentProfileData = Provider.of<RoomPageProvider>(context, listen: false).profiles;
    List<Room>? currentRoomsData = Provider.of<RoomPageProvider>(context, listen: false).rooms;

    // If this data is empty, then theres no need to render the stream. Return this.
    if(currentRoomsData!.isEmpty){
      return const Center(child: Center(child: Text('Click on an Avatar above and send them a message :) ')));
    }

    return StreamBuilder<List<Room>>(
      stream: roomsStream,
      builder: (context, snapshot) {
        if(snapshot.hasData) {
          //final rooms = snapshot.data!;
          return ListView.builder(
            scrollDirection: Axis.vertical,
            itemCount: rooms.length,
            itemBuilder: (BuildContext context, int index) {  
              Profile? otherUser = getProfileName(rooms[index].otherUserId, currentProfileData!);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10,10,10,0),
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.of(context).push(ChatPage.route(rooms[index].id)),
                    leading: Avatar(profile: otherUser),
                    title: Text(otherUser.username),
                    subtitle: Text(rooms[index].lastMessage == null ? 'Click here to send a message!' : rooms[index].lastMessage!.content),
                  )
                ),
              );
            }
          );
        }
        else {
          return preloader;
        }
      }
    );
  }
}


/*

 // Create a subscription to get realtime updates on room creation
    roomsStream = supabase
    .from('room_participants')
    .stream(primaryKey: ['room_id', 'profile_id'])
    .neq('profile_id', userId)
    .map((event) => event.map((e) => Room.fromRoomParticipants(e)).toList());


*/