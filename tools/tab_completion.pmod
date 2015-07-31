inherit Tools.Hilfe.Evaluator;
inherit Tools.Hilfe;

  mapping myvars = ([ ]);
  object server_fp;
  object mainhandler;
  Stdio.Readline readln = Stdio.Readline(Stdio.stdin);
  mapping(string:mixed) constants = constants;  //fetching Evaluator constants

mapping base_objects(Evaluator e)
{
  return all_constants() + e->constants + e->variables + myvars;
}

void set_server_filepath(object o)
{
  server_fp = o;
}

array(object|array(string)) resolv(Evaluator e, array completable,
                                   void|object base, void|string type)
{
  if (e->variables->DEBUG_COMPLETIONS)
    e->safe_write("resolv(%O, %O, %O)\n", completable, base, type);
  if (!sizeof(completable))
    return ({ base, completable, type });
  if (stringp(completable[0]) &&
      completable[0] == array_sscanf(completable[0], "%[ \t\r\n]")[0])
    return ({ base, completable[1..], type });
  if (typeof_token(completable[0]) == "argumentgroup" && type != "autodoc")
    return resolv(e, completable, master()->show_doc(base), "autodoc");
  int flag2 = 0;
  if(!base && completable[0]==".")
  {
    if (sizeof(completable) == 1)
      return ({ 0, completable, "module" });
    else
    {
      catch
      {
        // quick and dirty attempt to load a local module
         base=compile_string(sprintf("object o=.%s;", completable[1]), 0)()->o;
      };
      if (!base)
        return ({ 0, completable, type });
      if (objectp(base))
        return resolv(e, completable[2..], base, "module");
      return resolv(e, completable[2..], base);
    }
  }
  if (!base && sizeof(completable) > 1)
  {
    if (completable[0] == "master" && sizeof(completable) >=2
        && typeof_token(completable[1]) == "argumentgroup")
    {
      return resolv(e, completable[2..], master(), "object");
    }
    if (base=base_objects(e)[completable[0]])
    {
      return resolv(e, completable[1..], base, "object");
    }
    if ((sizeof(completable) > 1)
        && (base=master()->root_module[completable[0]]))
      return resolv(e, completable[1..], base, "module");
    return ({ 0, completable, type });
  }

  if (sizeof(completable) > 1)
  {
    object newbase;
    if (reference[completable[0]] && sizeof(completable) > 1)
      return resolv(e, completable[1..], base);
    if (type == "autodoc")
    {
      if (typeof_token(completable[0]) == "symbol"
          && (newbase = base->findObject(completable[0])))
        return resolv(e, completable[1..], newbase, type);
      else if (sizeof(completable) > 2
            && typeof_token(completable[0]) == "argumentgroup"
            && typeof_token(completable[1]) == "reference")
        return resolv(e, completable[2..], base, type);
      else
        return ({ base, completable, type });
    }
    if (!functionp(base) && (newbase=base[completable[0]]) )
      return resolv(e, completable[1..], newbase, type);
  }
  return ({ base, completable, type });
}


  array get_resolvable(array tokens, void|int debug)
  {
    
    array completable = ({});
    string tokentype;

    foreach(reverse(tokens);; string token)
    {
      string _tokentype = typeof_token(token);

      if (debug)
        write(sprintf("%O = %s\n", token, _tokentype));

      if ( ( _tokentype == "reference" &&
             (!tokentype || tokentype == "symbol"))
            || (_tokentype == "symbol" && (!tokentype
                 || (< "reference", "referencegroup",
                       "argumentgroup" >)[tokentype]))
            || ( (<"argumentgroup", "referencegroup" >)[_tokentype]
                 && (!tokentype || tokentype == "reference"))
         )
      {
        completable += ({ token });
        tokentype = _tokentype;
      }
      else if (_tokentype == "whitespace")
        ;
      else
        break;
    }

    // keep the last whitespace
    if (arrayp(tokens) && sizeof(tokens) &&
        typeof_token(tokens[-1]) == "whitespace")
      completable = ({ " " }) + completable;
    return reverse(completable);
  }


  void set(mapping vars)
  {
    myvars = vars;
  }

  void load_hilferc() {
    if(string home=getenv("HOME")||getenv("USERPROFILE"))
      if(string s=Stdio.read_file(home+"/.hilferc"))
  map(s/"\n", add_buffer);
  }


  array tokenize(string input)
  {
      array tokens = Parser.Pike.split(input);
      if (variables->DEBUG_COMPLETIONS)
          readln->message(sprintf("\n\ntokenize(%O): %O\n\n", input, tokens));
      // drop the linebreak that split appends
      if (tokens[-1] == "\n")
        tokens = tokens[..<1];
      else if (tokens[-1][-1] == '\n')
        tokens[-1] = tokens[-1][..<1];

      tokens = Parser.Pike.group(tokens);
      return tokens;
  }


string input;
  void handle_completions(string key)
  {
//    write("KEY IS : "+key);
    mixed old_handler = master()->get_inhibit_compile_errors();
    HilfeCompileHandler handler = HilfeCompileHandler(sizeof(backtrace()));
    master()->set_inhibit_compile_errors(handler);

    array tokens;
    input = readln->gettext()[..readln->getcursorpos()-1];
  //  write("INPUT IS "+input);
    array|string completions;

    mixed error = catch
    {
      tokens = tokenize(input);
    };
//    write("Tokens are : %O",tokens);

    int flag = 0;
    if(error)
    {
      if (objectp(error) && error->is_unterminated_string_error)
      {
        // THE set_attribute and get_attribute tab completion is here

        error = catch
        {
          array toks=({ });
          mixed error5 = catch{
            toks = tokenize(input+"\")");
          };
          if(error5==0)
          {
            int b = 0;
            b=search(toks,"set_attribute");
            if(b!=(sizeof(toks)-2)) //second last token is set_attribute, last token is the string inside with double quotes.
             b=search(toks,"query_attribute");
            if(b==(sizeof(toks)-2))  //because if set/query_attribute is at the end it will be second last token, which is -2
            {
             if(b!=-1)  //not needed
              {
                if((myvars[toks[b-2]]))   //usually it is like x->y->z->set_attribute(""), so z will be our const/var which is -2 from loc.
                {
                  completions = indices(base_objects(this)[toks[b-2]]->get_attributes());
                  string rest = toks[b+1][1]-"\"";
                  if(rest!="")
                  {
                    array(string) temp = ({ });
                    int i = 0;
                    int l = sizeof(rest);
                    foreach(completions, string str)
                    {
                     if(str[0 .. (l-1)]==rest)
                     {
                       temp = temp + ({str});
                       i++;
                     }
                    }
                    if(sizeof(temp)==1)
                      completions = (string)(temp[0]-rest);
                    else
                      completions = temp;
                   }
                   flag = 1;
                }
              }
            }
          }
          if(flag==0)
          {
            mixed outer_error = catch{
              array tokens3 = ({ });
              mixed error = catch{
                        tokens3 = tokenize(input+"\")");
              };
              if(error==0)
              {
                int a = 0;
                if((a=search(tokens3,"OBJ"))!=-1)
                {
                  int b = a+1;
                  if(arrayp(tokens3[b]))
                  {
                    completions = show_path_completions(tokens3[a+1][1]);
                  }
                  else
                    throw("no toks[a+1]\n");
                }
              }
            };
            if(outer_error)
              completions = get_file_completions((input/"\"")[-1]);
          }
        };
      }

      if (error)
      {
        if(!objectp(error))
          error = Error.mkerror(error);
        readln->message(sprintf("%s\nAn error occurred, attempting to complete your input!\nPlease include the backtrace above and the line below in your report:\ninput: %s\n", error->describe(), input));
        completions = ({});
      }
    }
    if (tokens && !completions)
    {
      array completable = get_resolvable(tokens, variables->DEBUG_COMPLETIONS);

      if (completable && sizeof(completable))
      {
        error = catch
        {
          completions = get_module_completions(completable);
        };
        error = Error.mkerror(error);
      }
      else if (!tokens || !sizeof(tokens))
        completions = sort(indices(master()->root_module)) +
          sort(indices(base_objects(this)));
        // FIXME: base_objects should not be sorted like this

      if (!completions || !sizeof(completions))
      {
        string token = tokens[-1];
        if( sizeof(tokens) >= 2 && typeof_token(token) == "whitespace" )
          token = tokens[-2];

        if (variables->DEBUG_COMPLETIONS)
          readln->message(sprintf("type: %s\n", typeof_token(token)));

        completions = sort(indices(master()->root_module)) +
          sort(indices(base_objects(this)));


        switch(typeof_token(token))
        {
          case "symbol":
          case "literal":
          case "postfix":
            completions = (array)(infix+seperator);
            break;
          case "prefix":
          case "infix":
          case "seperator":
          default:
            completions += (array)prefix;
        }
        foreach(reverse(tokens);; string token)
        {
            if (group[token])
            {
              completions += ({ group[token] }) ;
              break;
            }
        }
      }

      if (error)
      {
        readln->message(sprintf("%s\nAn error occurred, attempting to complete your input!\nPlease include the backtrace above and the lines below in your report:\ninput: %s\ntokens: %O\ncompletable: %O\n", error->describe(), input, tokens, completable, ));
      }
      else if (variables->DEBUG_COMPLETIONS)
        readln->message(sprintf("input: %s\ntokens: %O\ncompletable: %O\ncompletions: %O\n", input, tokens, completable, completions));
    }
    handler->show_errors();
    handler->show_warnings();
    master()->set_inhibit_compile_errors(old_handler);
//    write("Completions are %O",completions);
    if(completions && sizeof(completions))
    {
      if(stringp(completions))
      {
        readln->insert(completions, readln->getcursorpos());
      }
      else
      {
        readln->list_completions(completions);
      }
    }
  }

mixed show_path_completions(string cur_path)
{
  cur_path = cur_path - "\"";   //trimming "s in suppose "/"-> /
  mixed demo = ({ });
  if(cur_path=="")
  {
      demo = "/";
  }
  else
  {
    string rest="";
    array parts = ({});
    parts = cur_path/"/";
    if(sizeof(parts)!=2)
    {
      cur_path = parts[0 .. sizeof(parts)-2]*"/";
      rest = parts[-1];
    }
    else
    {
      cur_path="/";
      rest = parts[1];
    }
    object a;
    mixed error2 = catch{
      a = server_fp->path_to_object(cur_path);
    };
    array objs = ({ });
    mixed error= catch{
      string x_s="";
      objs=a->get_inventory();
      foreach(objs, object x)
      {
        if(cur_path!="/")
          x_s = x->query_attribute("OBJ_PATH") - cur_path - "/";
        else
          x_s = x->query_attribute("OBJ_PATH") - "/";
        mixed error3 = catch{
          if(x_s[0 .. sizeof(rest)-1]==rest)
            demo = demo + ({ x_s });
        };
      }
      if(sizeof(demo)==1)
      {
        demo = demo[0]-(rest);
        if(demo=="")
          demo = "/";
      }
      else if(sizeof(demo)!=0)
      {
        string common = String.common_prefix(demo);
        if((common!="")&&((common-rest)!=""))
          demo = common-(rest);
      }
    };
  }
  return demo;
}

mapping reftypes = ([ "module":".",
                     "object":"->",
                     "mapping":"->",
                     "function":"(",
                     "program":"(",
                     "method":"(",
                     "class":"(",
                   ]);

array low_get_module_completions(array completable, object base, void|string type, void|int(0..1) space)
{
  if (variables->DEBUG_COMPLETIONS)
    safe_write(sprintf("low_get_module_completions(%O\n, %O, %O, %O)\n", completable, base, type, space));

  if (!completable)
    completable = ({});

  mapping other = ([]);
  array modules = ({});
  mixed error;

   if (base && !sizeof(completable))
   {
     if (space)
       return (array)infix;
     if (type == "autodoc")
       return ({ reftypes[base->objtype||base->objects[0]->objtype]||"" });
     if (objectp(base))
       return ({ reftypes[type||"object"] });
     if (mappingp(base))
       return ({ reftypes->object });
     else if(functionp(base))
       return ({ reftypes->function });
     else if (programp(base))
       return ({ reftypes->program });
     else
       return (array)infix;
   }

      if (!base && sizeof(completable) && completable[0] == ".")
      {
          array modules = sort(get_dir("."));
          if (sizeof(completable) > 1)
          {
            modules = Array.filter(modules, has_prefix, completable[1]);
            if (sizeof(modules) == 1)
              return ({ (modules[0]/".")[0][sizeof(completable[1])..] });
            string prefix = String.common_prefix(modules)[sizeof(completable[1])..];
            if (prefix)
              return ({ prefix });

            if (sizeof(completable) == 2)
              return modules;
            else
              return ({});
          }
          else
            return modules;
      }
      else if (!base)
      {
          if (type == "autodoc")
          {
            if (variables->DEBUG_COMPLETIONS)
              safe_write("autodoc without base\n");
            return ({});
          }
          other = base_objects(this);
          base = master()->root_module;
      }

      if (type == "autodoc")
      {
        if (base->docGroups)
          modules = Array.uniq(Array.flatten(base->docGroups->objects->name));
        else
          return ({});
      }
      else
      {
        error = catch
        {
          modules = sort(indices(base));
        };
        error = Error.mkerror(error);
      }

      if (sizeof(other))
        modules += indices(other);

      if (sizeof(completable) == 1)
      {
          if (type == "autodoc"
              && typeof_token(completable[0]) == "argumentgroup")
            if (space)
              return (array)infix;
            else
              return ({ reftypes->object });
          if (reference[completable[0]])
            return modules;
          if (!stringp(completable[0]))
            return ({});


          modules = sort((array(string))modules);
          modules = Array.filter(modules, has_prefix, completable[0]);
          string prefix = String.common_prefix(modules);
          string module;

          if (prefix == completable[0] && sizeof(modules)>1 && (base[prefix]||other[prefix]))
            return modules + low_get_module_completions(({}), base[prefix]||other[prefix], type, space);

          prefix = prefix[sizeof(completable[0])..];
          if (sizeof(prefix))
            return ({ prefix });

          if (sizeof(modules)>1)
            return modules;
          else if (!sizeof(modules))
            return ({});
          else
          {
            module = modules[0];
            modules = ({});
            object thismodule;

            if(other && other[module])
            {
              thismodule = other[module];
              type = "object";
            }
            else if (intp(base[module]) || floatp(base[module]) || stringp(base[module]) )
              return (array)infix;
            else
            {
              thismodule = base[module];
              if (!type)
                type = "module";
            }

            return low_get_module_completions(({}), thismodule, type, space);
          }
      }

      if (completable && sizeof(completable))
      {
          if ( (< "reference", "argumentgroup" >)[typeof_token(completable[0])])
            return low_get_module_completions(completable[1..], base, type||reference[completable[0]], space);
          else
            safe_write(sprintf("UNHANDLED CASE: completable: %O\nbase: %O\n", completable, base));
      }

      return modules;
  }

  array|string get_module_completions(array completable)
  {
    array rest = completable;
    object base;
    string type;
    int(0..1) space;

    if (!completable)
      completable = ({});

    if (completable[-1]==' ')
    {
      space = true;
      completable = completable[..<1];
    }

    if (sizeof(completable) > 1)
      [base, rest, type] = resolv(this, completable);

    if (variables->DEBUG_COMPLETIONS)
      safe_write(sprintf("get_module_completions(%O): %O, %O, %O\n", completable, base, rest, type));
    array completions = low_get_module_completions(rest, base, type, space);
    if (sizeof(completions) == 1)
      return completions[0];
    else
      return completions;
  }
  array|string get_file_completions(string path)
  {
    array files = ({});
    if ( (< "", ".", ".." >)[path-"../"] )
      files += ({ ".." });

    if (!sizeof(path) || path[0] != '/')
      path = "./"+path;

    string dir = dirname(path);
    string file = basename(path);
    catch
    {
      files += get_dir(dir);
    };

    if (!sizeof(files))
      return ({});

    array completions = Array.filter(files, has_prefix, file);
    string prefix = String.common_prefix(completions)[sizeof(file)..];

    if (sizeof(prefix))
    {
      return prefix;
    }

    mapping filetypes = ([ "dir":"/", "lnk":"@", "reg":"" ]);

    if (sizeof(completions) == 1 && file_stat(dir+"/"+completions[0])->isdir )
    {
      return "/";
    }
    else
    {
      foreach(completions; int count; string item)
      {
        Stdio.Stat stat = file_stat(dir+"/"+item);
        if (stat)
          completions[count] += filetypes[stat->type]||"";

        stat = file_stat(dir+"/"+item, 1);
        if (stat->type == "lnk")
          completions[count] += filetypes["lnk"];
      }
      return completions;
    }
  }

