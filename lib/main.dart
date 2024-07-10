import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'package:intl/intl.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: InsightsPage(),
    );
  }
}

class InsightsPage extends StatefulWidget {
  @override
  _InsightsPageState createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  final String apiUrl = 'http://192.168.68.247/env_monitor/execute_query.php';
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<dynamic> _data = [];
  String _message = '';
  List<String> timestamps = [];
  List<FlSpot> humiditySpots = [];
  List<FlSpot> temperatureSpots = [];
  List<FlSpot> lightIntensitySpots = [];

  @override
  void initState() {
    super.initState();
    fetchInsights();
    initializeNotifications();

    // Set up the timer to fetch insights every 5 seconds
    Timer.periodic(Duration(seconds: 5), (timer) {
      fetchInsights();
    });

    // Set up the timer to fetch notifications every 30 seconds
    Timer.periodic(Duration(seconds: 30), (timer) {
      fetchLatestNotifications().then((notifications) {
        checkForNotification(notifications);
      }).catchError((error) {
        print('Error fetching notifications: $error');
      });
    });
  }

  void initializeNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onSelectNotification: onSelectNotification);
  }

  Future<void> fetchInsights() async {
    try {
      final response =
          await http.get(Uri.parse('$apiUrl?fetch_latest_insights=true'));

      if (response.statusCode == 200) {
        setState(() {
          _data = json.decode(response.body);
          // print('Data fetched: $_data');
          updateChartData(_data);
          checkForNotification(_data);
        });
      } else {
        setState(() {
          _message = 'Failed to load insights: ${response.statusCode}';
        });
        print(_message);
      }
    } catch (e) {
      setState(() {
        _message = 'Error: $e';
      });
      print(_message);
    }
  }

  void updateChartData(List<dynamic> insights) {
    // Clear existing data
    humiditySpots.clear();
    temperatureSpots.clear();
    lightIntensitySpots.clear();
    timestamps.clear();

    insights.forEach((insight) {
      // Parse timestamp and convert to milliseconds since epoch
      double timestamp = DateTime.parse(insight['timestamp'])
          .millisecondsSinceEpoch
          .toDouble();

      // Ensure numeric values are treated as double and formatted to two decimal places
      double avgHumidity = (insight['avg_humidity'] ?? 0.0).toDouble();
      double avgTemperature = (insight['avg_temperature'] ?? 0.0).toDouble();

      // Format values to two decimal places
      String formattedAvgHumidity = avgHumidity.toStringAsFixed(2);
      String formattedAvgTemperature = avgTemperature.toStringAsFixed(2);

      // Print parsed values after conversion
      double parsedAvgHumidity = double.parse(formattedAvgHumidity);
      double parsedAvgTemperature = double.parse(formattedAvgTemperature);

      // Add data to FlSpot lists, parsing formatted values as double
      humiditySpots.add(FlSpot(timestamp, parsedAvgHumidity));
      temperatureSpots.add(FlSpot(timestamp, parsedAvgTemperature));

      // Format timestamp to HH:mm:ss
      timestamps.add(
          DateFormat('HH:mm:ss').format(DateTime.parse(insight['timestamp'])));

      // Remove old entries if more than 5
      if (humiditySpots.length > 5) {
        humiditySpots.removeAt(0);
        temperatureSpots.removeAt(0);
        timestamps.removeAt(0);
      }
    });

    // Ensure there are always at least 5 data points
    while (humiditySpots.length < 5) {
      humiditySpots.insert(0, FlSpot(0, 0));
      temperatureSpots.insert(0, FlSpot(0, 0));
      timestamps.insert(0, '00:00:00');
    }

    // Trigger UI update
    setState(() {});
  }

  Future<List<dynamic>> fetchLatestNotifications() async {
    final response = await http.get(Uri.parse(
        'http://192.168.68.247/env_monitor/execute_query.php?fetch_latest_notifications=true'));

    if (response.statusCode == 200) {
      // If the server returns a 200 OK response, parse the JSON
      List<dynamic> notifications = jsonDecode(response.body);
      return notifications;
    } else {
      // If the server returns an error response, throw an exception
      throw Exception('Failed to load notifications');
    }
  }

  void checkForNotification(List<dynamic> notifications) {
    if (notifications.isNotEmpty) {
      notifications.forEach((notification) {
        if (notification.containsKey('message') &&
            notification['message'] is String &&
            notification['message'].isNotEmpty &&
            notification['message'] != "All is good") {
          showNotification(notification['message']);
        }
      });
    }
  }

  Future<void> showNotification(String message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      icon: 'app_icon', // Make sure this icon exists in your project
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Alert',
      message,
      platformChannelSpecifics,
      payload: message, // Use the fetched notification message as payload
    );
  }

  Future<void> onSelectNotification(String? payload) async {
    if (payload != null) {
      debugPrint('notification payload: $payload');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notification'),
          content: Text(payload),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Home'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_data.isNotEmpty)
                Column(
                  children: [
                    _buildInsightCard(
                      'Average Humidity',
                      '${_data.last['avg_humidity']} %',
                      Icons.water_drop,
                      Colors.lightBlue.shade100,
                    ),
                    _buildInsightCard(
                      'Min Humidity',
                      '${_data.last['min_humidity']} %',
                      Icons.water,
                      Colors.lightBlue.shade100,
                    ),
                    _buildInsightCard(
                      'Max Humidity',
                      '${_data.last['max_humidity']} %',
                      Icons.water_damage,
                      Colors.lightBlue.shade100,
                    ),
                    BarChartWidget(
                      values: humiditySpots.map((spot) => spot.y).toList(),
                      timestamps: timestamps,
                      label: 'Humidity',
                      color: Colors.lightBlue,
                    ),
                    _buildInsightCard(
                      'Average Temperature',
                      '${_data.last['avg_temperature']} °C',
                      Icons.thermostat,
                      Colors.red.shade100,
                    ),
                    _buildInsightCard(
                      'Min Temperature',
                      '${_data.last['min_temperature']} °C',
                      Icons.ac_unit,
                      Colors.red.shade100,
                    ),
                    _buildInsightCard(
                      'Max Temperature',
                      '${_data.last['max_temperature']} °C',
                      Icons.local_fire_department,
                      Colors.red.shade100,
                    ),
                    BarChartWidget(
                      values: temperatureSpots.map((spot) => spot.y).toList(),
                      timestamps: timestamps,
                      label: 'Temperature',
                      color: Colors.red,
                    ),
                    _buildInsightCard(
                      'Average Light Intensity',
                      '${_data.last['avg_light_intensity']} lx',
                      Icons.light,
                      Colors.yellow.shade100,
                    ),
                    _buildInsightCard(
                      'Min Light Intensity',
                      '${_data.last['min_light_intensity']} lx',
                      Icons.light_mode,
                      Colors.yellow.shade100,
                    ),
                    _buildInsightCard(
                      'Max Light Intensity',
                      '${_data.last['max_light_intensity']} lx',
                      Icons.wb_sunny,
                      Colors.yellow.shade100,
                    ),
                    _buildLightIntensityCard(),
                  ],
                )
              else if (_message.isNotEmpty)
                Text(_message),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLightIntensityCard() {
    double avgLightIntensity =
        _data.last['avg_light_intensity']?.toDouble() ?? 0.0;
    Color bulbColor = getColorForLightIntensity(avgLightIntensity);
    String lightEffect = getEffectForLightIntensity(avgLightIntensity);

    return Card(
      color: Colors.yellow.shade100,
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(2), // Adjust padding as needed
          decoration: BoxDecoration(
            color: Color.fromARGB(255, 180, 180, 180), // Black background color
            borderRadius: BorderRadius.circular(8), // Border radius
          ),
          child: Icon(Icons.lightbulb, color: bulbColor),
        ),
        title: Text('Light Intensity Effect'),
        trailing: Text(
          lightEffect,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Color getColorForLightIntensity(double intensity) {
    if (intensity <= 0.3) return Colors.black;
    if (intensity <= 2) return Colors.grey.shade800;
    if (intensity <= 10) return Colors.grey.shade600;
    if (intensity <= 50) return Colors.yellow.shade900;
    if (intensity <= 100) return Colors.yellow.shade700;
    if (intensity <= 200) return Colors.yellow;
    if (intensity <= 400) return Colors.yellow.shade200;
    if (intensity <= 800) return Colors.yellow.shade100;
    return Colors.white;
  }

  String getEffectForLightIntensity(double intensity) {
    if (intensity <= 0.3) return 'Blinding';
    if (intensity <= 2) return 'Dark';
    if (intensity <= 10) return 'Dusky';
    if (intensity <= 50) return 'Gloomy';
    if (intensity <= 100) return 'Dim Light';
    if (intensity <= 200) return 'Satisfactory Light';
    if (intensity <= 400) return 'Good Light';
    if (intensity <= 600) return 'Bright Light';
    if (intensity <= 800) return 'Glaring Light';
    return 'Bright Sunlight';
  }

  Widget _buildInsightCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      color: color,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 15, // Adjust font size here
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class BarChartWidget extends StatelessWidget {
  final List<double> values;
  final List<String> timestamps;
  final String label;
  final Color color;

  BarChartWidget({
    required this.values,
    required this.timestamps,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300, // Increased the height of the chart
      padding: const EdgeInsets.all(16.0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: values.isNotEmpty
              ? values.reduce((a, b) => a > b ? a : b) + 10
              : 0,
          barGroups: values.asMap().entries.map((entry) {
            int index = entry.key;
            double value = entry.value;
            return BarChartGroupData(
              x: index, // Use index as x value
              barRods: [
                BarChartRodData(
                  y: value,
                  colors: [color],
                  width: 20, // Adjust bar width here
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: SideTitles(
              showTitles: true,
              getTitles: (double value) {
                int idx = value.toInt();
                if (idx >= 0 && idx < timestamps.length) {
                  return timestamps[idx];
                }
                return '';
              },
              rotateAngle: 25, // Rotate the x-axis labels
            ),
            leftTitles: SideTitles(
              showTitles: true,
              getTitles: (double value) {
                if (value % 20 == 0) {
                  return value
                      .toInt()
                      .toString(); // Convert double to int and then to string
                }
                return '';
              },
            ),
          ),
        ),
      ),
    );
  }
}
