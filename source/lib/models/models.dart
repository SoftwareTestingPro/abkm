enum UserRole {
  member,    // 0
  moderator, // 1
  admin,     // 2
  superUser, // 3
  blocked,   // 4
}

enum EventType {
  meeting,    // 0
  rally,      // 1
  andolan,    // 2
  dharna,     // 3
  conference, // 4
  protest,    // 5
  other,      // 6
  announcement,     // 7
}

class ABKMUser {
  final String id;
  final String name;
  final String gender;
  final String? maritalStatus;
  final DateTime? dob;
  final UserRole userRole;
  final String bio;
  final String? profileImageUrl;
  final String state;
  final String district;
  final String tehsil;
  final String village;
  final String sector;
  final String profession;
  final String education;
  final String? referralMobile;
  final String position;
  final bool isBlocked;
  final bool isDeleted;
  final int points;
  final int referralCount;
  final DateTime? lastLogin;
  final String? blockedBy;

  ABKMUser({
    required this.id,
    required this.name,
    required this.gender,
    this.maritalStatus,
    this.dob,
    required this.userRole,
    required this.bio,
    this.profileImageUrl,
    this.state = '',
    this.district = '',
    this.tehsil = '',
    this.village = '',
    this.sector = '',
    this.profession = '',
    this.education = '',
    this.referralMobile,
    this.position = 'Member',
    this.isBlocked = false,
    this.isDeleted = false,
    this.points = 0,
    this.referralCount = 0,
    this.lastLogin,
    this.blockedBy,
  });

  int get age {
    if (dob != null) {
      final now = DateTime.now();
      int age = now.year - dob!.year;
      if (now.month < dob!.month || (now.month == dob!.month && now.day < dob!.day)) {
        age--;
      }
      return age;
    }
    return 25; // Default fallback if DOB is missing
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'gender': gender,
    'marital_status': maritalStatus,
    'dob': dob?.toIso8601String(),
    'user_role': userRole.index,
    'bio': bio,
    'profile_image_url': profileImageUrl,
    'state': state,
    'district': district,
    'tehsil': tehsil,
    'village': village,
    'sector': sector,
    'profession': profession,
    'education': education,
    'referral_mobile': referralMobile,
    'position': position,
    'is_blocked': isBlocked,
    'is_deleted': isDeleted,
    'points': points,
    'referral_count': referralCount,
    'last_login': lastLogin?.toUtc().toIso8601String(),
    'blocked_by': blockedBy,
  };

  factory ABKMUser.fromJson(Map<String, dynamic> json) => ABKMUser(
    id: json['id'],
    name: json['name'] ?? 'Anonymous',
    gender: json['gender'] ?? 'Other',
    maritalStatus: json['marital_status'] ?? json['maritalStatus'],
    dob: json['dob'] != null ? DateTime.parse(json['dob']) : null,
    userRole: (json['user_role'] ?? json['userRole']) != null && (json['user_role'] ?? json['userRole']) < UserRole.values.length 
        ? UserRole.values[json['user_role'] ?? json['userRole']] 
        : UserRole.member,
    bio: json['bio'] ?? '',
    profileImageUrl: json['profile_image_url'] ?? json['profileImageUrl'],
    state: json['state'] ?? '',
    district: json['district'] ?? '',
    tehsil: json['tehsil'] ?? '',
    village: json['village'] ?? '',
    sector: json['sector'] ?? '',
    profession: json['profession'] ?? '',
    education: json['education'] ?? '',
    referralMobile: json['referral_mobile'] ?? json['referralMobile'],
    position: json['position'] ?? 'Member',
    isBlocked: json['is_blocked'] ?? json['isBlocked'] ?? false,
    isDeleted: json['is_deleted'] ?? json['isDeleted'] ?? false,
    points: json['points'] ?? (json['referral_count'] != null ? (json['referral_count'] * 5) : 0),
    referralCount: json['referral_count'] ?? json['referralCount'] ?? 0,
    lastLogin: json['last_login'] != null ? DateTime.parse(json['last_login']).toLocal() : null,
    blockedBy: json['blocked_by'] ?? json['blockedBy'],
  );

  ABKMUser copyWith({
    String? id,
    String? name,
    String? gender,
    String? maritalStatus,
    DateTime? dob,
    UserRole? userRole,
    String? bio,
    String? profileImageUrl,
    String? state,
    String? district,
    String? tehsil,
    String? village,
    String? sector,
    String? profession,
    String? education,
    String? referralMobile,
    String? position,
    bool? isBlocked,
    bool? isDeleted,
    int? points,
    int? referralCount,
    DateTime? lastLogin,
    String? blockedBy,
  }) {
    return ABKMUser(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      dob: dob ?? this.dob,
      userRole: userRole ?? this.userRole,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      state: state ?? this.state,
      district: district ?? this.district,
      tehsil: tehsil ?? this.tehsil,
      village: village ?? this.village,
      sector: sector ?? this.sector,
      profession: profession ?? this.profession,
      education: education ?? this.education,
      referralMobile: referralMobile ?? this.referralMobile,
      position: position ?? this.position,
      isBlocked: isBlocked ?? this.isBlocked,
      isDeleted: isDeleted ?? this.isDeleted,
      points: points ?? this.points,
      referralCount: referralCount ?? this.referralCount,
      lastLogin: lastLogin ?? this.lastLogin,
      blockedBy: blockedBy ?? this.blockedBy,
    );
  }
}

class ABKMEvent {
  final String id;
  final String hostId; 
  final String title;
  final String description;
  final DateTime date;
  final String village;
  final EventType eventType;
  final List<String> approvedMemberIds;
  final String imageUrl;
  final String district;
  final String state;
  final String tehsil;
  final bool isApproved;
  final bool isDeclined;
  final String? meetingPoint;

  ABKMEvent({
    required this.id,
    required this.hostId,
    required this.title,
    required this.description,
    required this.date,
    required this.village,
    required this.eventType,
    this.approvedMemberIds = const [],
    required this.imageUrl,
    this.district = '',
    this.state = '',
    this.tehsil = '',
    this.isApproved = false,
    this.isDeclined = false,
    this.meetingPoint,
  });

  ABKMEvent copyWith({
    String? id,
    String? hostId,
    String? title,
    String? description,
    DateTime? date,
    String? village,
    EventType? eventType,
    List<String>? approvedMemberIds,
    String? imageUrl,
    String? district,
    String? state,
    String? tehsil,
    bool? isApproved,
    bool? isDeclined,
    String? meetingPoint,
  }) {
    return ABKMEvent(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      village: village ?? this.village,
      eventType: eventType ?? this.eventType,
      approvedMemberIds: approvedMemberIds ?? this.approvedMemberIds,
      imageUrl: imageUrl ?? this.imageUrl,
      district: district ?? this.district,
      state: state ?? this.state,
      tehsil: tehsil ?? this.tehsil,
      isApproved: isApproved ?? this.isApproved,
      isDeclined: isDeclined ?? this.isDeclined,
      meetingPoint: meetingPoint ?? this.meetingPoint,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'host_id': hostId,
    'title': title,
    'description': description,
    'date': date.toUtc().toIso8601String(),
    'village': village,
    'event_type': eventType.index,
    'approved_member_ids': approvedMemberIds,
    'image_url': imageUrl,
    'district': district,
    'state': state,
    'tehsil': tehsil,
    'is_approved': isApproved,
    'is_declined': isDeclined,
    'meeting_point': meetingPoint,
  };

  factory ABKMEvent.fromJson(Map<String, dynamic> json) => ABKMEvent(
    id: json['id'],
    hostId: json['host_id'] ?? json['hostId'],
    title: json['title'],
    description: json['description'] ?? '',
    date: DateTime.parse(json['date'].toString().endsWith('Z') || json['date'].toString().contains('+') || json['date'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? json['date'] : '${json['date']}Z').toLocal(),
    village: json['village'] ?? json['location'] ?? '',
    eventType: () {
      final idx = json['event_type'] ?? json['eventType'] ?? 0;
      if (idx == 5) return EventType.dharna; // Map old protest to dharna
      return idx < EventType.values.length ? EventType.values[idx] : EventType.other;
    }(),
    approvedMemberIds: List<String>.from(json['approved_member_ids'] ?? json['approvedMemberIds'] ?? []),
    imageUrl: (json['image_url'] ?? json['imageUrl']) != null && ((json['image_url'] ?? json['imageUrl']).toString().startsWith('assets/') || (json['image_url'] ?? json['imageUrl']).toString().startsWith('/9j/')) 
        ? (json['image_url'] ?? json['imageUrl']) 
        : 'assets/images/${(() {
            final idx = json['event_type'] ?? json['eventType'] ?? 0;
            if (idx == 5) return EventType.dharna;
            return idx < EventType.values.length ? EventType.values[idx] : EventType.other;
          })().name}.jpg',
    district: json['district'] ?? json['city'] ?? '',
    state: json['state'] ?? '',
    tehsil: json['tehsil'] ?? '',
    isApproved: json['is_approved'] ?? json['isApproved'] ?? true,
    isDeclined: json['is_declined'] ?? json['isDeclined'] ?? false,
    meetingPoint: json['meeting_point'] ?? json['meetingPoint'],
  );
}

enum ApplicationStatus { pending, approved, declined, withdrawn, invitationPending, invitationAccepted, invitationDeclined }

class EventApplication {
  final String id;
  final String eventId;
  final String applicantId;
  final String message;
  final bool isApproved;
  final ApplicationStatus status;
  final bool isInvitation;
  final DateTime? createdAt;

  EventApplication({
    required this.id,
    required this.eventId,
    required this.applicantId,
    this.message = '',
    this.isApproved = false,
    this.status = ApplicationStatus.pending,
    this.isInvitation = false,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'applicantId': applicantId,
    'message': message,
    'isApproved': isApproved,
    'status': status.index,
    'isInvitation': isInvitation,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };

  factory EventApplication.fromJson(Map<String, dynamic> json) => EventApplication(
    id: json['id'],
    eventId: json['eventId'],
    applicantId: json['applicantId'],
    message: json['message'] ?? '',
    isApproved: json['isApproved'] ?? false,
    status: (json['status'] ?? 0) < ApplicationStatus.values.length 
        ? ApplicationStatus.values[json['status'] ?? 0] 
        : ApplicationStatus.pending,
    isInvitation: json['isInvitation'] ?? false,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString().endsWith('Z') || json['created_at'].toString().contains('+') || json['created_at'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? json['created_at'] : '${json['created_at']}Z').toLocal() : null,
  );
}

enum PromotionStatus { pending, approved, declined }

class PromotionRequest {
  final String id;
  final String userId;
  final String requesterId; // ID of Admin who requested it (if any)
  final String targetRole; // e.g. 'admin'
  final PromotionStatus status;
  final DateTime createdAt;

  PromotionRequest({
    required this.id,
    required this.userId,
    required this.requesterId,
    this.targetRole = 'admin',
    this.status = PromotionStatus.pending,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'requesterId': requesterId,
    'targetRole': targetRole,
    'status': status.index,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory PromotionRequest.fromJson(Map<String, dynamic> json) => PromotionRequest(
    id: json['id'],
    userId: json['userId'],
    requesterId: json['requesterId'],
    targetRole: json['targetRole'] ?? 'admin',
    status: (json['status'] ?? 0) < PromotionStatus.values.length 
        ? PromotionStatus.values[json['status'] ?? 0] 
        : PromotionStatus.pending,
    createdAt: DateTime.parse(json['created_at']).toLocal(),
  );
}
