#include <roles.h>
#include <classes.h>

class Role {
  static int         iRoles;
  static object     oDomain;
  static mapping attrDomain;
  static string       sDesc;

  void create(string desc, int accBits, object domain, void|mapping attr) {
    sDesc = desc;
    iRoles = accBits;
    oDomain = domain;
    attrDomain = attr;
  }

  // The rolebits associated with this role, for example read permissions,
  // but also password, etc.
  int get_rolebits() {
    return iRoles;
  }
  
  int check_environment(object obj) {
    if ( !objectp(obj) )
      return 0;
    else if ( obj == oDomain )
      return 1;
    return check_environment(obj->get_environment());
  }

  int check(int permission, RoleContext ctx) {
    //werror("Checking " + describe() + " for "+ ctx->describe() + "\n");
    // if ctx is part of domain and permission matches return true !
    if ( objectp(oDomain) ) {
	if ( oDomain->get_object_class() & CLASS_GROUP ) {
	    if ( oDomain->is_member(ctx) )
		return 1;
	    return 0;
	}
	if ( oDomain->get_object_class() & CLASS_ROOM ) 
	    return check_environment(ctx);
	return 0;
    }
    if ( mappingp(attrDomain) ) {
	return 0;
    }
    return permission & iRoles;
  }

  // The domain of objects this role is restricted to. For example
  // a group of users or a container (which includes all objects within).
  // If no object is set then the access is unrestricted.
  object|void get_domain() {
    return oDomain;
  }
  
  string describe() {
    return "Role("+sDesc+","+iRoles + ", domain=[" +oDomain->describe()+"])";
  }

  string get_name() {
    return sDesc;
  }
  
  // are the roles restricted to some attributes
  mapping|void get_attributes() {
    return attrDomain;
  }

  // save a role
  mapping save() {
    return ([
      "roles": iRoles,
      "domain": oDomain,
      "attributes": attrDomain,
      "description": sDesc,
    ]);
  }
};

class RoleList {
  mapping roles;
  
  void create() {
    roles = ([ ]);
  }
  
  void add(Role r) {
    if ( !objectp(roles[r->get_name()]) )
      roles[r->get_name()] = r;
  }
  
  int check(int permission, RoleContext ctx) {
    foreach( values(roles), Role r )
      if ( r->check(permission, ctx) )
	return 1;
    return 0;
  }
  
  void load(mapping data) {
    foreach ( values(data), mapping d ) {
      roles[d->description]=Role(d->description, d->roles, d->domain, d->attributes);
    }
  }
  
  mapping save() {
    mapping sv = ([ ]);
    foreach ( values(roles), Role r ) {
      sv[r->get_name()] = r->save();
    }
    return sv;
  }
  
  string describe() {
    string desc =  "List ";
    foreach( values(roles), Role r )
      desc += ". " + r->describe();
    return desc;
  }
}


class RoleContext {
  object domain;
  void|mixed value;

  void create(object d, mixed|void v) {
    domain = d;
    value = v;
  }
  string describe() {
    return "Context:"+domain->describe() + sprintf(" : %O",value);
  }
}








