// ignore_for_file: prefer_const_constructors, unnecessary_const
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BarangayBoundary {
  final String name;
  final List<double> bbox; // [minLat, minLng, maxLat, maxLng]
  final List<double> center; // [centerLat, centerLng]
  final List<List<double>> polygon; // [[lng, lat], ...]

  const BarangayBoundary({
    required this.name,
    required this.bbox,
    required this.center,
    required this.polygon,
  });
}

class GeocodingResult {
  final bool success;
  final String? barangay;
  final String? municipality;
  final String? province;
  final String? street;
  final String formattedAddress;
  final bool isWithinPozorrubio;
  final String source;
  final double lat;
  final double lng;

  const GeocodingResult({
    required this.success,
    this.barangay,
    this.municipality,
    this.province,
    this.street,
    required this.formattedAddress,
    required this.isWithinPozorrubio,
    required this.source,
    required this.lat,
    required this.lng,
  });

  @override
  String toString() =>
      'GeocodingResult(barangay: $barangay, municipality: $municipality, province: $province, formattedAddress: "$formattedAddress", isWithinPozorrubio: $isWithinPozorrubio)';
}

class BarangayService {
  static int _latestGeocodeId = 0;

  static const double minLat = 16.0500;
  static const double maxLat = 16.1800;
  static const double minLng = 120.4800;
  static const double maxLng = 120.6100;

  static const List<BarangayBoundary> boundaries = [
    const BarangayBoundary(
      name: 'Alipangpang',
      bbox: [16.104914, 120.549183, 16.113484, 120.57508],
      center: [16.109159, 120.560778],
      polygon: [[120.558251, 16.109912], [120.551822, 16.113408], [120.549365, 16.113484], [120.549183, 16.109998], [120.549288, 16.105609], [120.551138, 16.106187], [120.561026, 16.106302], [120.565766, 16.104914], [120.566844, 16.105514], [120.57181, 16.108456], [120.57508, 16.109813], [120.574449, 16.112483], [120.568667, 16.111001], [120.560736, 16.110391], [120.558251, 16.109912]],
    ),
    const BarangayBoundary(
      name: 'Amagbagan',
      bbox: [16.075278, 120.527285, 16.098074, 120.551366],
      center: [16.087005, 120.53827],
      polygon: [[120.551366, 16.09608], [120.537737, 16.097067], [120.536936, 16.098074], [120.531164, 16.097535], [120.527882, 16.097226], [120.528497, 16.091489], [120.527693, 16.088542], [120.527285, 16.087874], [120.528086, 16.084724], [120.532297, 16.075508], [120.534344, 16.075278], [120.537042, 16.077144], [120.537491, 16.079808], [120.540526, 16.079424], [120.543458, 16.077855], [120.543767, 16.081339], [120.547915, 16.083991], [120.550264, 16.086113], [120.550275, 16.088949], [120.551366, 16.09608]],
    ),
    const BarangayBoundary(
      name: 'Balacag',
      bbox: [16.118659, 120.482289, 16.143566, 120.501973],
      center: [16.13241, 120.492538],
      polygon: [[120.501973, 16.125684], [120.497623, 16.128166], [120.496287, 16.136967], [120.498079, 16.143566], [120.495249, 16.141717], [120.492508, 16.140556], [120.485671, 16.139143], [120.482289, 16.138828], [120.483319, 16.135293], [120.483791, 16.124219], [120.487604, 16.122845], [120.49663, 16.118659], [120.501973, 16.125684]],
    ),
    const BarangayBoundary(
      name: 'Banding',
      bbox: [16.09608, 120.551138, 16.106302, 120.566844],
      center: [16.102246, 120.559287],
      polygon: [[120.566844, 16.105514], [120.565766, 16.104914], [120.561026, 16.106302], [120.551138, 16.106187], [120.551382, 16.102496], [120.551366, 16.09608], [120.553514, 16.09617], [120.560757, 16.097817], [120.564238, 16.101471], [120.566844, 16.105514]],
    ),
    const BarangayBoundary(
      name: 'Bantugan',
      bbox: [16.087045, 120.498394, 16.096041, 120.52017],
      center: [16.092862, 120.509525],
      polygon: [[120.514854, 16.095518], [120.508341, 16.096041], [120.505647, 16.095244], [120.504525, 16.095668], [120.501061, 16.09466], [120.498394, 16.095383], [120.498569, 16.092617], [120.505273, 16.087082], [120.518507, 16.087045], [120.52017, 16.088645], [120.518011, 16.090316], [120.515618, 16.093474], [120.514854, 16.095518]],
    ),
    const BarangayBoundary(
      name: 'Batakil',
      bbox: [16.13485, 120.515575, 16.148157, 120.53074],
      center: [16.141171, 120.523521],
      polygon: [[120.53074, 16.142286], [120.52913, 16.148157], [120.523209, 16.147961], [120.516139, 16.146036], [120.515575, 16.142556], [120.518895, 16.139155], [120.519927, 16.137441], [120.519998, 16.13485], [120.522592, 16.137616], [120.52254, 16.139307], [120.525131, 16.13916], [120.526838, 16.140304], [120.527838, 16.139278], [120.53074, 16.142286]],
    ),
    const BarangayBoundary(
      name: 'Bobonan',
      bbox: [16.122356, 120.512757, 16.142286, 120.540764],
      center: [16.132521, 120.526281],
      polygon: [[120.540764, 16.134619], [120.532515, 16.135747], [120.53074, 16.142286], [120.527838, 16.139278], [120.526838, 16.140304], [120.525131, 16.13916], [120.52254, 16.139307], [120.522592, 16.137616], [120.519998, 16.13485], [120.516889, 16.132909], [120.516999, 16.13129], [120.513958, 16.129029], [120.512757, 16.126797], [120.517368, 16.122356], [120.517259, 16.125379], [120.518031, 16.125848], [120.528642, 16.130379], [120.530003, 16.128313], [120.532046, 16.128609], [120.53505, 16.128747], [120.53806, 16.13001], [120.537671, 16.13052], [120.540764, 16.134619]],
    ),
    const BarangayBoundary(
      name: 'Buneg',
      bbox: [16.109912, 120.558251, 16.129222, 120.574507],
      center: [16.118685, 120.566796],
      polygon: [[120.574449, 16.112483], [120.574507, 16.115913], [120.573385, 16.123197], [120.572343, 16.124513], [120.569758, 16.126372], [120.568022, 16.129222], [120.559301, 16.127447], [120.561405, 16.120715], [120.561067, 16.118991], [120.55881, 16.11895], [120.558251, 16.109912], [120.560736, 16.110391], [120.568667, 16.111001], [120.574449, 16.112483]],
    ),
    const BarangayBoundary(
      name: 'Cablong',
      bbox: [16.113468, 120.533972, 16.123682, 120.549365],
      center: [16.118848, 120.543003],
      polygon: [[120.548798, 16.121934], [120.542771, 16.122434], [120.541751, 16.123682], [120.539985, 16.122399], [120.533972, 16.11888], [120.534312, 16.115975], [120.540608, 16.113807], [120.544107, 16.113468], [120.549365, 16.113484], [120.548571, 16.119326], [120.548798, 16.121934]],
    ),
    const BarangayBoundary(
      name: 'Casanfernandoan',
      bbox: [16.105306, 120.48239, 16.124219, 120.49732],
      center: [16.115618, 120.489352],
      polygon: [[120.49663, 16.118659], [120.487604, 16.122845], [120.483791, 16.124219], [120.48239, 16.119355], [120.482966, 16.114409], [120.485005, 16.105306], [120.491832, 16.106921], [120.49732, 16.11019], [120.49663, 16.118659]],
    ),
    const BarangayBoundary(
      name: 'Castaño',
      bbox: [16.09466, 120.49732, 16.11019, 120.514854],
      center: [16.101168, 120.505577],
      polygon: [[120.511038, 16.107181], [120.504516, 16.106037], [120.500625, 16.106397], [120.49732, 16.11019], [120.49793, 16.103815], [120.498394, 16.095383], [120.501061, 16.09466], [120.504525, 16.095668], [120.505647, 16.095244], [120.508341, 16.096041], [120.514854, 16.095518], [120.512063, 16.099102], [120.510731, 16.103931], [120.511038, 16.107181]],
    ),
    const BarangayBoundary(
      name: 'Dilan',
      bbox: [16.074742, 120.514812, 16.088645, 120.532297],
      center: [16.083108, 120.522858],
      polygon: [[120.527693, 16.088542], [120.52017, 16.088645], [120.518507, 16.087045], [120.516785, 16.083618], [120.514812, 16.078436], [120.515722, 16.074742], [120.522391, 16.076516], [120.532297, 16.075508], [120.528086, 16.084724], [120.527285, 16.087874], [120.527693, 16.088542]],
    ),
    const BarangayBoundary(
      name: 'Don Benito',
      bbox: [16.125349, 120.496287, 16.146611, 120.50968],
      center: [16.13401, 120.503717],
      polygon: [[120.505777, 16.126226], [120.505747, 16.130333], [120.507746, 16.133443], [120.50968, 16.139466], [120.507834, 16.146611], [120.50236, 16.146081], [120.498079, 16.143566], [120.496287, 16.136967], [120.497623, 16.128166], [120.501973, 16.125684], [120.505718, 16.125349], [120.505777, 16.126226]],
    ),
    const BarangayBoundary(
      name: 'Haway',
      bbox: [16.092617, 120.485005, 16.11019, 120.498569],
      center: [16.100809, 120.493776],
      polygon: [[120.498394, 16.095383], [120.49793, 16.103815], [120.49732, 16.11019], [120.491832, 16.106921], [120.485005, 16.105306], [120.487528, 16.101785], [120.489012, 16.095879], [120.498569, 16.092617], [120.498394, 16.095383]],
    ),
    const BarangayBoundary(
      name: 'Imbalbalatong',
      bbox: [16.109912, 120.548571, 16.128022, 120.561405],
      center: [16.121156, 120.554446],
      polygon: [[120.557069, 16.127832], [120.55098, 16.128022], [120.549738, 16.124697], [120.550003, 16.123637], [120.548798, 16.121934], [120.548571, 16.119326], [120.549365, 16.113484], [120.551822, 16.113408], [120.558251, 16.109912], [120.55881, 16.11895], [120.561067, 16.118991], [120.561405, 16.120715], [120.559301, 16.127447], [120.557069, 16.127832]],
    ),
    const BarangayBoundary(
      name: 'Inoman',
      bbox: [16.134619, 120.52913, 16.151996, 120.549103],
      center: [16.141172, 120.541093],
      polygon: [[120.549103, 16.137209], [120.546494, 16.141913], [120.544322, 16.146415], [120.541203, 16.151996], [120.52913, 16.148157], [120.53074, 16.142286], [120.532515, 16.135747], [120.540764, 16.134619], [120.54756, 16.136169], [120.549103, 16.137209]],
    ),
    const BarangayBoundary(
      name: 'Laoac',
      bbox: [16.126226, 120.505747, 16.146611, 120.519998],
      center: [16.136145, 120.513604],
      polygon: [[120.516139, 16.146036], [120.507834, 16.146611], [120.50968, 16.139466], [120.507746, 16.133443], [120.505747, 16.130333], [120.505777, 16.126226], [120.512757, 16.126797], [120.513958, 16.129029], [120.516999, 16.13129], [120.516889, 16.132909], [120.519998, 16.13485], [120.519927, 16.137441], [120.518895, 16.139155], [120.515575, 16.142556], [120.516139, 16.146036]],
    ),
    const BarangayBoundary(
      name: 'Maambal',
      bbox: [16.076004, 120.483729, 16.095879, 120.503324],
      center: [16.086754, 120.493417],
      polygon: [[120.498569, 16.092617], [120.489012, 16.095879], [120.486108, 16.091677], [120.483729, 16.083214], [120.492598, 16.077079], [120.503324, 16.076004], [120.495427, 16.084947], [120.498569, 16.092617]],
    ),
    const BarangayBoundary(
      name: 'Malasin',
      bbox: [16.088542, 120.514854, 16.097226, 120.528497],
      center: [16.092135, 120.522219],
      polygon: [[120.527693, 16.088542], [120.528497, 16.091489], [120.527882, 16.097226], [120.519554, 16.095464], [120.514854, 16.095518], [120.515618, 16.093474], [120.518011, 16.090316], [120.52017, 16.088645], [120.527693, 16.088542]],
    ),
    const BarangayBoundary(
      name: 'Malokiat',
      bbox: [16.106037, 120.49663, 16.125684, 120.511038],
      center: [16.115279, 120.504322],
      polygon: [[120.505718, 16.125349], [120.501973, 16.125684], [120.49663, 16.118659], [120.49732, 16.11019], [120.500625, 16.106397], [120.504516, 16.106037], [120.511038, 16.107181], [120.510295, 16.109208], [120.506551, 16.113101], [120.506009, 16.114565], [120.505466, 16.121627], [120.505718, 16.125349]],
    ),
    const BarangayBoundary(
      name: 'Manaol',
      bbox: [16.107181, 120.505466, 16.126797, 120.531911],
      center: [16.117488, 120.515298],
      polygon: [[120.517368, 16.122356], [120.512757, 16.126797], [120.505777, 16.126226], [120.505718, 16.125349], [120.505466, 16.121627], [120.506009, 16.114565], [120.506551, 16.113101], [120.510295, 16.109208], [120.511038, 16.107181], [120.518745, 16.10855], [120.531911, 16.110703], [120.531241, 16.116297], [120.529457, 16.116457], [120.517899, 16.119354], [120.517169, 16.119676], [120.517368, 16.122356]],
    ),
    const BarangayBoundary(
      name: 'Nama',
      bbox: [16.121934, 120.537671, 16.139262, 120.557069],
      center: [16.129553, 120.548237],
      polygon: [[120.557069, 16.127832], [120.556045, 16.13148], [120.55672, 16.137267], [120.555932, 16.139262], [120.549103, 16.137209], [120.54756, 16.136169], [120.540764, 16.134619], [120.537671, 16.13052], [120.53806, 16.13001], [120.54, 16.125793], [120.541751, 16.123682], [120.542771, 16.122434], [120.548798, 16.121934], [120.550003, 16.123637], [120.549738, 16.124697], [120.55098, 16.128022], [120.557069, 16.127832]],
    ),
    const BarangayBoundary(
      name: 'Nantangalan',
      bbox: [16.074742, 120.495427, 16.092617, 120.518507],
      center: [16.082107, 120.509193],
      polygon: [[120.518507, 16.087045], [120.505273, 16.087082], [120.498569, 16.092617], [120.495427, 16.084947], [120.503324, 16.076004], [120.505613, 16.076101], [120.508589, 16.075543], [120.515722, 16.074742], [120.514812, 16.078436], [120.516785, 16.083618], [120.518507, 16.087045]],
    ),
    const BarangayBoundary(
      name: 'Palacpalac',
      bbox: [16.11888, 120.531089, 16.13001, 120.541751],
      center: [16.125141, 120.536735],
      polygon: [[120.541751, 16.123682], [120.54, 16.125793], [120.53806, 16.13001], [120.53505, 16.128747], [120.532046, 16.128609], [120.531089, 16.128162], [120.53365, 16.121449], [120.533972, 16.11888], [120.539985, 16.122399], [120.541751, 16.123682]],
    ),
    const BarangayBoundary(
      name: 'Palguyod',
      bbox: [16.115975, 120.517169, 16.130379, 120.534312],
      center: [16.12305, 120.526946],
      polygon: [[120.532046, 16.128609], [120.530003, 16.128313], [120.528642, 16.130379], [120.518031, 16.125848], [120.517259, 16.125379], [120.517368, 16.122356], [120.517169, 16.119676], [120.517899, 16.119354], [120.529457, 16.116457], [120.531241, 16.116297], [120.534312, 16.115975], [120.533972, 16.11888], [120.53365, 16.121449], [120.531089, 16.128162], [120.532046, 16.128609]],
    ),
    const BarangayBoundary(
      name: 'Poblacion I',
      bbox: [16.108094, 120.531241, 16.116297, 120.544107],
      center: [16.113025, 120.536548],
      polygon: [[120.534312, 16.115975], [120.531241, 16.116297], [120.531911, 16.110703], [120.531831, 16.108094], [120.544064, 16.109883], [120.544107, 16.113468], [120.540608, 16.113807], [120.534312, 16.115975]],
    ),
    const BarangayBoundary(
      name: 'Poblacion II',
      bbox: [16.105831, 120.531831, 16.109883, 120.54411],
      center: [16.107876, 120.53939],
      polygon: [[120.544064, 16.109883], [120.531831, 16.108094], [120.532069, 16.105831], [120.540203, 16.107061], [120.54411, 16.106501], [120.544064, 16.109883]],
    ),
    const BarangayBoundary(
      name: 'Poblacion III',
      bbox: [16.109883, 120.544064, 16.113484, 120.549365],
      center: [16.112063, 120.547217],
      polygon: [[120.549365, 16.113484], [120.544107, 16.113468], [120.544064, 16.109883], [120.549183, 16.109998], [120.549365, 16.113484]],
    ),
    const BarangayBoundary(
      name: 'Poblacion IV',
      bbox: [16.105609, 120.544064, 16.109998, 120.549288],
      center: [16.107331, 120.547185],
      polygon: [[120.549288, 16.105609], [120.549183, 16.109998], [120.544064, 16.109883], [120.54411, 16.106501], [120.547177, 16.106385], [120.549288, 16.105609]],
    ),
    const BarangayBoundary(
      name: 'Rosario',
      bbox: [16.085605, 120.550275, 16.109813, 120.581737],
      center: [16.096793, 120.568689],
      polygon: [[120.550275, 16.088949], [120.55672, 16.090277], [120.561258, 16.090694], [120.561154, 16.085605], [120.573199, 16.088406], [120.577837, 16.089159], [120.579418, 16.089071], [120.580079, 16.090643], [120.579378, 16.096405], [120.57949, 16.097682], [120.581737, 16.100621], [120.581336, 16.103648], [120.579025, 16.106187], [120.576372, 16.107835], [120.57508, 16.109813], [120.57181, 16.108456], [120.566844, 16.105514], [120.564238, 16.101471], [120.560757, 16.097817], [120.553514, 16.09617], [120.551366, 16.09608], [120.550275, 16.088949]],
    ),
    const BarangayBoundary(
      name: 'Sugcong',
      bbox: [16.137209, 120.541203, 16.153458, 120.562407],
      center: [16.146082, 120.55447],
      polygon: [[120.562407, 16.143755], [120.561055, 16.147609], [120.560566, 16.150829], [120.560842, 16.153458], [120.553032, 16.152719], [120.552315, 16.152279], [120.541203, 16.151996], [120.544322, 16.146415], [120.546494, 16.141913], [120.549103, 16.137209], [120.555932, 16.139262], [120.555056, 16.141702], [120.557848, 16.142241], [120.562407, 16.143755]],
    ),
    const BarangayBoundary(
      name: 'Talogtog',
      bbox: [16.09608, 120.531164, 16.107061, 120.551382],
      center: [16.102944, 120.543057],
      polygon: [[120.54411, 16.106501], [120.540203, 16.107061], [120.532069, 16.105831], [120.531164, 16.097535], [120.536936, 16.098074], [120.537737, 16.097067], [120.551366, 16.09608], [120.551382, 16.102496], [120.551138, 16.106187], [120.549288, 16.105609], [120.547177, 16.106385], [120.54411, 16.106501]],
    ),
    const BarangayBoundary(
      name: 'Tulnac',
      bbox: [16.095464, 120.510731, 16.110703, 120.532069],
      center: [16.103102, 120.522806],
      polygon: [[120.531831, 16.108094], [120.531911, 16.110703], [120.518745, 16.10855], [120.511038, 16.107181], [120.510731, 16.103931], [120.512063, 16.099102], [120.514854, 16.095518], [120.519554, 16.095464], [120.527882, 16.097226], [120.531164, 16.097535], [120.532069, 16.105831], [120.531831, 16.108094]],
    ),
    const BarangayBoundary(
      name: 'Villegas',
      bbox: [16.127447, 120.555056, 16.143755, 120.568077],
      center: [16.135236, 120.561163],
      polygon: [[120.568022, 16.129222], [120.568077, 16.132632], [120.565449, 16.137114], [120.565171, 16.138894], [120.562407, 16.143755], [120.557848, 16.142241], [120.555056, 16.141702], [120.555932, 16.139262], [120.55672, 16.137267], [120.556045, 16.13148], [120.557069, 16.127832], [120.559301, 16.127447], [120.568022, 16.129222]],
    ),
  ];

  /// Ray-casting point-in-polygon algorithm.
  /// [x] is longitude, [y] is latitude.
  /// [vs] is list of [lng, lat] polygon vertices.
  static bool pointInPolygon(double x, double y, List<List<double>> vs) {
    bool inside = false;
    for (int i = 0, j = vs.length - 1; i < vs.length; j = i++) {
      final xi = vs[i][0];
      final yi = vs[i][1];
      final xj = vs[j][0];
      final yj = vs[j][1];

      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Haversine formula distance between two coordinates in meters.
  static double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // meters
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final deltaPhi = (lat2 - lat1) * math.pi / 180.0;
    final deltaLambda = (lon2 - lon1) * math.pi / 180.0;

    final a = math.sin(deltaPhi / 2.0) * math.sin(deltaPhi / 2.0) +
        math.cos(phi1) * math.cos(phi2) *
        math.sin(deltaLambda / 2.0) * math.sin(deltaLambda / 2.0);
    final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
    return r * c;
  }

  /// Authoritatively find which Pozorrubio barangay contains the given coordinates.
  static BarangayBoundary? findPozorrubioBarangay(double lat, double lng) {
    // 1. Exact Polygon Point-in-Polygon Check
    for (final b in boundaries) {
      final bMinLat = b.bbox[0];
      final bMinLng = b.bbox[1];
      final bMaxLat = b.bbox[2];
      final bMaxLng = b.bbox[3];

      if (lat >= bMinLat && lat <= bMaxLat && lng >= bMinLng && lng <= bMaxLng) {
        if (pointInPolygon(lng, lat, b.polygon)) {
          return b;
        }
      }
    }

    // 2. Buffer tolerance check: If within broad Pozorrubio geofence, snap to nearest barangay
    if (lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng) {
      BarangayBoundary? closest;
      double minDist = double.infinity;

      for (final b in boundaries) {
        final dist = haversineDistance(lat, lng, b.center[0], b.center[1]);
        if (dist < minDist) {
          minDist = dist;
          closest = b;
        }
      }

      if (closest != null && minDist <= 3000) {
        return closest;
      }
    }

    return null;
  }

  /// Resolve full administrative location with authoritative boundary enforcement.
  /// Prevents stale async responses using sequential request IDs.
  static Future<GeocodingResult> resolveLocation(double lat, double lng) async {
    final requestId = ++_latestGeocodeId;
    debugPrint('[BarangayService] Resolving GPS Coordinates: lat=$lat, lng=$lng (requestId=$requestId)');

    // Step 1: Check authoritative PSGC Pozorrubio boundaries
    final pozMatch = findPozorrubioBarangay(lat, lng);

    if (pozMatch != null) {
      final barangay = pozMatch.name;
      const municipality = 'Pozorrubio';
      const province = 'Pangasinan';
      String? street;

      // Non-blocking query to fetch road/street name only
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
        );
        final res = await http.get(
          uri,
          headers: {'User-Agent': 'com.alertopoz.app', 'Accept-Language': 'en'},
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final addr = data['address'] as Map<String, dynamic>?;
          street = addr?['road']?.toString() ?? addr?['pedestrian']?.toString();
        }
      } catch (_) {
        // Non-critical: street name is optional
      }

      // Check if another request was triggered while waiting
      if (requestId != _latestGeocodeId) {
        debugPrint('[BarangayService] Discarding stale geocode response ($requestId superseded by $_latestGeocodeId)');
      }

      final parts = <String>[];
      if (street != null && street.isNotEmpty) parts.add(street);
      parts.add(barangay);
      parts.add(municipality);
      parts.add(province);

      final result = GeocodingResult(
        success: true,
        barangay: barangay,
        municipality: municipality,
        province: province,
        street: street,
        formattedAddress: parts.join(', '),
        isWithinPozorrubio: true,
        source: 'authoritative_psgc',
        lat: lat,
        lng: lng,
      );

      debugPrint('[BarangayService] Authoritative Match: Barangay="$barangay", Municipality="$municipality", Province="$province" (Full: "${result.formattedAddress}")');
      return result;
    }

    // Step 2: Coordinates are outside Pozorrubio - query external geocoder with strict hierarchy mapping
    debugPrint('[BarangayService] Coordinates ($lat, $lng) outside Pozorrubio, querying external geocoder');
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final res = await http.get(
        uri,
        headers: {'User-Agent': 'com.alertopoz.app', 'Accept-Language': 'en'},
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      final addr = (data['address'] as Map<String, dynamic>?) ?? {};

      var brgy = addr['village'] ??
          addr['suburb'] ??
          addr['quarter'] ??
          addr['hamlet'] ??
          addr['neighbourhood'] ??
          addr['city_district'] ??
          '';
      var brgyStr = brgy.toString().trim();
      if (brgyStr.toLowerCase().startsWith('barangay ')) {
        brgyStr = brgyStr.substring(9).trim();
      }

      final town = addr['town'] ??
          addr['municipality'] ??
          addr['city'] ??
          addr['county'] ??
          '';
      final prov = addr['province'] ??
          addr['state'] ??
          addr['region'] ??
          '';
      final street = addr['road']?.toString() ?? addr['pedestrian']?.toString();

      final parts = <String>[];
      if (brgyStr.isNotEmpty) parts.add(brgyStr);
      if (town.toString().isNotEmpty) parts.add(town.toString());
      if (prov.toString().isNotEmpty) parts.add(prov.toString());

      final result = GeocodingResult(
        success: true,
        barangay: brgyStr.isNotEmpty ? brgyStr : null,
        municipality: town.toString().isNotEmpty ? town.toString() : null,
        province: prov.toString().isNotEmpty ? prov.toString() : null,
        street: street,
        formattedAddress: parts.isNotEmpty ? parts.join(', ') : (data['display_name'] ?? 'Unknown Location'),
        isWithinPozorrubio: false,
        source: 'external_nominatim',
        lat: lat,
        lng: lng,
      );

      debugPrint('[BarangayService] External Geocode Result: Barangay="$brgyStr", Municipality="$town", Province="$prov"');
      return result;
    } catch (e) {
      debugPrint('[BarangayService] Reverse geocode error: $e');
      return GeocodingResult(
        success: false,
        barangay: null,
        municipality: null,
        province: null,
        formattedAddress: 'Unknown Location',
        isWithinPozorrubio: false,
        source: 'failed',
        lat: lat,
        lng: lng,
      );
    }
  }
}
