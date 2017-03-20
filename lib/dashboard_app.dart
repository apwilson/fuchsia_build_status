// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:core';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

enum BuildStatus { UNKNOWN, NETWORKERROR, PARSEERROR, SUCCESS, FAILURE }

// ----------------------------------------------------------------------------
// EDIT BELOW TO ADD configs

final String kBaseURL = 'https://luci-scheduler.appspot.com/jobs/';

class BuildInfo {
  BuildStatus status = BuildStatus.UNKNOWN;
  String url;

  BuildInfo({this.status, this.url});
}

var targets_map = {
  'fuchsia': [
    ['fuchsia/linux-x86-64-debug', 'linux-x86-64-debug'],
    ['fuchsia/linux-arm64-debug', 'linux-arm64-debug'],
    ['fuchsia/linux-x86-64-release', 'linux-x86-64-release'],
    ['fuchsia/linux-arm64-release', 'linux-arm64-release'],
  ],
  'fuchsia-drivers': [
    ['fuchsia/drivers-linux-x86-64-debug', 'linux-x86-64-debug'],
    ['fuchsia/drivers-linux-arm64-debug', 'linux-arm64-debug'],
    ['fuchsia/drivers-linux-x86-64-release', 'linux-x86-64-release'],
    ['fuchsia/drivers-linux-arm64-release', 'linux-arm64-release'],
  ],
  'magenta': [
    ['magenta/arm64-linux-gcc', 'arm64-linux-gcc'],
    ['magenta/x86-64-linux-gcc', 'x86-64-linux-gcc'],
    ['magenta/arm64-linux-clang', 'arm64-linux-clang'],
    ['magenta/x86-64-linux-clang', 'x86-64-linux-clang'],
  ],
  'jiri': [
    ['jiri/linux-x86-64', 'linux-x86-64'],
    ['jiri/mac-x86-64', 'mac-x86-64'],
  ]
};

class DashboardApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Fuchsia Build Status',
      theme: new ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: new DashboardPage(title: 'Fuchsia Build Status'),
    );
  }
}

class DashboardPage extends StatefulWidget {
  DashboardPage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _DashboardPageState createState() => new _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  BuildStatus _status = BuildStatus.UNKNOWN;
  var targets_results;
  Timer _refresh_timer;
  DateTime _start_time = new DateTime.now();

  @override
  initState() {
    // From the targets map, create a data structure which we'll be populating
    // the build results into, as they come in async.
    targets_results = new Map();

    targets_map.forEach((categoryName, buildConfigs) {
      var this_map = new Map<String, BuildInfo>();
      for (var config in buildConfigs) {
        this_map[config[1]] = new BuildInfo(
          status: BuildStatus.UNKNOWN,
          url: "http://www.google.com",
        );
      }
      targets_results[categoryName] = this_map;
    });

    _refresh_timer = new Timer.periodic(
      const Duration(seconds: 60),
      _refreshTimerFired,
    );
    _refreshStatus();
  }

  void _refreshTimerFired(Timer t) {
    _refreshStatus();
  }

  // Refresh status an ALL builds.
  void _refreshStatus() {
    // fetch config status for ONE item.
    _fetchConfigStatus(categoryName, buildName, url) async {
      BuildStatus status = BuildStatus.PARSEERROR;
      String html = null;

      try {
        var response = await http.get(url);
        html = response.body;
      } catch (error) {
        status = BuildStatus.NETWORKERROR;
      }

      if (html == null) {
        status = BuildStatus.NETWORKERROR;
      } else {
        var dom_tree = parse(html);
        List<dom.Element> trs = dom_tree.querySelectorAll('tr');
        for (var tr in trs) {
          if (tr.className == "danger") {
            status = BuildStatus.FAILURE;
            break;
          } else if (tr.className == "success") {
            status = BuildStatus.SUCCESS;
            break;
          }
        }
      }

      targets_results['${categoryName}']['${buildName}'].status = status;
      targets_results['${categoryName}']['${buildName}'].url = url;
      setState(() {});
    } // _fetchConfigStatus

    // kick off requests for all the build configs desired. As
    // these reults come in they will be stuffed into the targets_results map.
    targets_map.forEach((categoryName, buildConfigs) {
      for (var config in buildConfigs) {
        String url = kBaseURL + config[0];
        _fetchConfigStatus(categoryName, config[1], url);
      }
    }); // targets_forEach
  } // _refreshStatus

  void _launchUrl(String url) {
    UrlLauncher.launch(url);
  }

  Color _colorFromBuildStatus(BuildStatus status) {
    switch (status) {
      case BuildStatus.SUCCESS:
        return Colors.green[100];
      case BuildStatus.FAILURE:
        return Colors.red[400];
      case BuildStatus.NETWORKERROR:
        return Colors.purple[100];
      default:
        return Colors.black12;
    }
  }

  Widget _buildResultWidget(String name, BuildInfo bi) {
    return new Expanded(
      child: new GestureDetector(
        onTap: () {
          _launchUrl(bi.url);
        },
        child: new Container(
          decoration: new BoxDecoration(
            backgroundColor: _colorFromBuildStatus(bi.status),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
          margin: const EdgeInsets.fromLTRB(0.0, 8.0, 8.0, 8.0),
          child: new Text(
            name,
            style: new TextStyle(color: Colors.black, fontSize: 12.0),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance
    // as done by the _refreshStatus method above.

    if (ui.window.physicalSize.width > ui.window.physicalSize.height)
      return _buildLandcape(context);
    else
      return _buildPortrait(context);
  }

  Widget _buildPortrait(BuildContext context) {
    return _buildLandcape(context); // TODO
  }

  Widget _buildLandcape(BuildContext context) {
    var rows = new List();

    Duration uptime = new DateTime.now().difference(_start_time);

    rows.add(
      new Container(
        child: new Text(
          "${uptime.inDays}d ${uptime.inHours % 24}h ${uptime.inMinutes % 60}m uptime",
          style: new TextStyle(fontSize: 11.0),
        ),
      ),
    );

    targets_results.forEach((k, v) {
      // the builds
      var builds = new List();
      v.forEach((name, status_obj) {
        builds.add(_buildResultWidget("${k}\n${name}", status_obj));
      });

      rows.add(
        new Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          mainAxisSize: MainAxisSize.max,
          children: builds,
        ),
      );
    });

    return new Scaffold(
      appBar: Platform.isFuchsia
          ? null
          : new AppBar(title: new Text('Fuchsia Build Status')),
      body: new Container(
        //padding: new EdgeInsets.all(20.0),
        child: new Column(
          children: rows,
        ),
      ),
      floatingActionButton: new FloatingActionButton(
        onPressed: _refreshStatus,
        tooltip: 'Increment',
        child: new Icon(Icons.refresh),
      ),
    );
  }
}
