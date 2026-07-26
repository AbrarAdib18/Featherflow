import 'package:flutter/material.dart';

typedef PhosphorIconData = IconData;

class PhosphorIconsStyle {
  static const fill = 'fill';
}

class PhosphorIcon extends Icon {
  const PhosphorIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
  });
}

class PhosphorIcons {
  static IconData arrowLeft() => Icons.arrow_back;
  static IconData feather() => Icons.eco;
  static IconData plus() => Icons.add;
  static IconData magnifyingGlass() => Icons.search;
  static IconData funnel() => Icons.filter_alt;
  static IconData arrowsDownUp() => Icons.swap_vert;
  static IconData caretDown() => Icons.arrow_drop_down;
  static IconData article() => Icons.article;
  static IconData microscope() => Icons.science;
  static IconData firstAid() => Icons.medical_services;
  static IconData newspaper() => Icons.newspaper;
  static IconData lightbulb() => Icons.lightbulb;
  static IconData leaf() => Icons.park;
  static IconData chartBar() => Icons.bar_chart;
  static IconData clock() => Icons.access_time;
  static IconData bookmarkSimple([Object? style]) => Icons.bookmark;
  static IconData shareNetwork() => Icons.share;
  static IconData dotsThree() => Icons.more_horiz;
  static IconData pushPin([Object? style]) => Icons.push_pin;
  static IconData arrowRight() => Icons.arrow_forward;
  static IconData checkCircle([Object? style]) => Icons.check_circle;
  static IconData pencilSimple() => Icons.edit;
  static IconData bell() => Icons.notifications;
  static IconData hash() => Icons.tag;
  static IconData image() => Icons.image;
  static IconData calendarBlank() => Icons.calendar_today;
  static IconData calendar() => Icons.calendar_today;
  static IconData user() => Icons.person;
  static IconData users() => Icons.people;
  static IconData house() => Icons.home;
  static IconData warning() => Icons.warning;
}
