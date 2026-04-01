import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';

class PassengerCountPage extends StatefulWidget {
  const PassengerCountPage({super.key});

  @override
  State<PassengerCountPage> createState() => _PassengerCountPageState();
}

class _PassengerCountPageState extends State<PassengerCountPage> {
  List<dynamic> _places = [];
  bool _isLoading = false;

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    fetchPlaces();
  }

  // ✅ FETCH PLACES
  Future<void> fetchPlaces() async {
    setState(() => _isLoading = true);

    final url = Uri.parse(
      "https://api.geoapify.com/v2/places"
      "?categories=commercial"
      "&filter=circle:121.03,14.63,5000"
      "&limit=20"
      "&apiKey=bd51332a72a04236810720cd5621d350",
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      setState(() {
        _places = data['features'];
      });
    }

    setState(() => _isLoading = false);
  }

  // ✅ GEOCODING SEARCH
  Future<void> _searchLocation() async {
    final query = _searchController.text;

    if (query.isEmpty) return;

    setState(() => _isLoading = true);

    final url = Uri.parse(
      "https://api.geoapify.com/v1/geocode/search"
      "?text=${Uri.encodeComponent(query)}"
      "&apiKey=e605752aebb54fbdbf1e12762e32077e",
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['features'].isNotEmpty) {
        final coords = data['features'][0]['geometry']['coordinates'];

        final lng = coords[0];
        final lat = coords[1];

        // ✅ Move map
        _mapController.move(LatLng(lat, lng), 15);
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),

      body: Column(
        children: [
          // 🔹 SEARCH BAR
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "Search landmark...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _searchLocation,
                  child: const Icon(Icons.search),
                ),
              ],
            ),
          ),

          // 🔹 MAP
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(14.63, 121.03),
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                      ),

                      MarkerLayer(
                        markers: _places.map((place) {
                          final coords = place['geometry']['coordinates'];

                          return Marker(
                            point: LatLng(coords[1], coords[0]),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.blue,
                              size: 30,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
          ),

          // 🔹 FOOTER
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text("Footer Section"),
          ),
        ],
      ),
    );
  }
}
