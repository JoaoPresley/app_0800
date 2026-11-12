import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'dart:convert';

class Api {
  //Constructor
  Api(
    {
      required String this.link,
      http.Client? client
    }) : _client = client ?? http.Client();
  
  //Atributes
  String link;
  final http.Client _client;

  //Metods
  Future<void> login()  async{
    // Initial link
    Uri url = Uri.https(link);
    
    try{
      final http.Response resp = await _client.get(url);
      if (resp.statusCode == 200){
        print(resp.body);
      }else{
        throw Exception('Erro a acessar link: $link');
      }
    }catch(e){
      throw e.toString();
    }
  }
}