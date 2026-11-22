
/* WARNING: Removing unreachable block (ram,0x000115b1) */
/* WARNING: Heritage AFTER dead removal. Example location: r0x00015226 : 0x000113a7 */
/* WARNING: Globals starting with '_' overlap smaller symbols at the same address */
/* WARNING: Restarted to delay deadcode elimination for space: ram */

void __cdecl16far entry(void)

{
  uint uVar1;
  uint uVar2;
  uint uVar3;
  uint uVar4;
  undefined2 uVar5;
  undefined2 uVar6;
  undefined2 uVar7;
  undefined1 local_102 [242];
  undefined1 local_10 [2];
  undefined1 local_e [2];
  undefined1 local_c [2];
  undefined1 local_a [2];
  undefined1 local_8 [2];
  undefined1 local_6 [4];
  
  uVar5 = 0x1000;
  if (DAT_1000_f2d0 == '\x01') {
    DAT_1000_f2d0 = '\0';
    _DAT_1000_f2ae = 1;
    uVar5 = 0xc89;
    func_0x0000fdcf(0x1000);
  }
  uVar6 = uVar5;
  if ((_DAT_1000_cac2 == 3) &&
     (((_DAT_1000_be5c == 0xbb || (_DAT_1000_be5c == 0xc3)) || (_DAT_1000_be5c == 0xc4)))) {
    uVar6 = 0x1bab;
    func_0x0001bffd(uVar5,0xf);
    DAT_1000_f2d0 = '\x01';
  }
  if ((_DAT_1000_cac2 == 1) &&
     (((_DAT_1000_be5c == 0x35 || (_DAT_1000_be5c == 0x142)) ||
      ((_DAT_1000_be5c == 0x16a || (_DAT_1000_be5c == 0x1fb)))))) {
    func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0,uVar6);
    func_0x0000f86c(0x2a97);
    _DAT_1000_cae8 = 1;
  }
  else {
    if ((_DAT_1000_cac2 == 0x39) && ((_DAT_1000_be5c == 0x49 || (_DAT_1000_be5c == 0x45)))) {
      _DAT_1000_cac2 = 3;
    }
    if ((((DAT_1000_be1b < 0x12) || (0x16 < DAT_1000_be1b)) && (DAT_1000_be1b < 0x19)) &&
       (DAT_1000_5e31 == '\x01')) {
      uVar5 = uVar6;
      if (DAT_1000_f301 == '\x03') {
        uVar5 = 0xc89;
        func_0x00016c68(uVar6,0x108);
      }
      if (((_DAT_1000_cae2 < 3) || (DAT_1000_f301 != '\0')) || (_DAT_1000_cac2 == 4)) {
        if ((_DAT_1000_cae2 < 5) || (DAT_1000_f301 != '\x01')) {
          uVar6 = uVar5;
          if ((6 < _DAT_1000_cae2) && (DAT_1000_f301 == '\x02')) {
            uVar6 = 0xc89;
            func_0x00016c68(uVar5,0x108);
            DAT_1000_f301 = '\x03';
          }
        }
        else {
          func_0x00016c68(uVar5,0x107);
          DAT_1000_f301 = '\x02';
          uVar6 = 0xc89;
        }
      }
      else {
        func_0x00016c68(uVar5,0x105);
        DAT_1000_f301 = '\x01';
        uVar6 = 0xc89;
      }
    }
    if ((((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x46)) && (_DAT_1000_452a == -0x40)) &&
       (DAT_1000_f2f8 == '\0')) {
      DAT_1000_f377 = DAT_1000_f377 + '\x01';
      _DAT_1000_452a = -1;
      DAT_1000_f2f8 = '\x01';
      if (DAT_1000_f2e5 == '\0') {
        DAT_1000_f2e5 = '\x01';
        _DAT_1000_cae4 = _DAT_1000_cae4 + 0x32;
      }
      func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0x1c,uVar6);
      func_0x0000f86c(0x2a97);
      _DAT_1000_cae8 = 1;
    }
    else if ((_DAT_1000_cac2 == 2) && (_DAT_1000_be5c == 0x46)) {
      func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0x41,uVar6);
      func_0x0000f86c(0x2a97);
      func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x6a,0xc89);
      func_0x0000f86c(0x2a97);
      _DAT_1000_cae8 = 1;
    }
    else if ((_DAT_1000_cac2 == 4) && (_DAT_1000_be5c == 0x172)) {
      func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0x88,uVar6);
      func_0x0000f86c(0x2a97);
      _DAT_1000_cae8 = 1;
    }
    else {
      uVar5 = uVar6;
      if ((_DAT_1000_cac2 == 0x39) && (_DAT_1000_be5c == 0x15)) {
        if (_DAT_1000_44c8 == -1) {
          uVar5 = 0xc89;
          func_0x00016c68(uVar6,0x91);
          _DAT_1000_cae8 = 1;
        }
        else {
          func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0xc9,uVar6);
          uVar5 = 0xc89;
          func_0x0000f86c(0x2a97);
          _DAT_1000_cae8 = 1;
        }
      }
      if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x1f)) {
        func_0x00016c68(uVar5,0xc1);
        if (DAT_1000_5e03 == '\0') {
          func_0x00016c68(0xc89,0xc2);
        }
        else {
          func_0x00016c68(0xc89,0xc3);
        }
        _DAT_1000_cae8 = 1;
      }
      else {
        if ((((_DAT_1000_cac2 == 4) || (_DAT_1000_cac2 == 0x13)) &&
            (((_DAT_1000_be5c == 0x41 || (_DAT_1000_be5c == 0x40)) && (DAT_1000_f302 != 2)))) &&
           ((_DAT_1000_be5e == 0x60 || (_DAT_1000_be5e == 0x62)))) {
          _DAT_1000_cac2 = 0x66;
          _DAT_1000_be5c = 0x41;
          _DAT_1000_be5e = 0x60;
        }
        if (((_DAT_1000_cac2 == 0x66) || (_DAT_1000_cac2 == 4)) && (_DAT_1000_be5e == 0x41)) {
          _DAT_1000_cac2 = 0x66;
          _DAT_1000_be5e = _DAT_1000_be5c;
          _DAT_1000_be5c = 0x41;
        }
        if (((((_DAT_1000_cac2 == 0x66) || (_DAT_1000_cac2 == 4)) && (_DAT_1000_be5c == 0x41)) &&
            ((_DAT_1000_be5e == 0x60 || (_DAT_1000_be5e == 0x62)))) && (DAT_1000_f302 < 2)) {
          func_0x00016c68(uVar5,0x172);
          _DAT_1000_cae8 = 1;
          DAT_1000_f302 = 2;
          _DAT_1000_4520 = 0xffff;
          DAT_1000_5181 = 1;
          _DAT_1000_387e = 0;
          if (DAT_1000_f2e4 == '\0') {
            DAT_1000_f2e4 = '\x01';
            _DAT_1000_cae4 = _DAT_1000_cae4 + 10;
          }
        }
        else if ((_DAT_1000_cac2 == 0x66) && ((_DAT_1000_be5e == 0x62 || (_DAT_1000_be5c == 0x62))))
        {
          func_0x00016c68(uVar5,0x21a);
          _DAT_1000_cae8 = 1;
        }
        else if ((_DAT_1000_cac2 == 0x66) && (_DAT_1000_be5c == 0x1d)) {
          func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0xec,uVar5);
          func_0x0000f86c(0x2a97);
          _DAT_1000_cae8 = 1;
        }
        else if (((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x4a)) && (DAT_1000_f303 == '\0')) {
          DAT_1000_f303 = '\x01';
          func_0x00016c68(uVar5,0x151);
          _DAT_1000_cae8 = 1;
        }
        else if (DAT_1000_f303 == '\x01') {
          DAT_1000_f303 = '\x02';
          func_0x00016c68(uVar5,0x15a);
          _DAT_1000_cae8 = 1;
        }
        else if (DAT_1000_f303 == '\x02') {
          if (_DAT_1000_cac2 == 0x43) {
            func_0x00016c68(uVar5,0x15c);
            _DAT_1000_cae8 = 1;
            DAT_1000_f303 = '\x01';
          }
          else {
            DAT_1000_f303 = '\x03';
            func_0x00016c68(uVar5,0x160);
            _DAT_1000_cae8 = 1;
          }
        }
        else if ((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x81)) {
          func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x11b,uVar5);
          func_0x0000f86c(0x2a97);
          _DAT_1000_cae8 = 1;
        }
        else {
          if (((_DAT_1000_cac2 == 4) || (_DAT_1000_cac2 == 0x13)) &&
             ((_DAT_1000_be5c == 0x41 || (_DAT_1000_be5c == 0x40)))) {
            if (DAT_1000_f302 == 0) {
              func_0x00016c68(uVar5,0x169);
              _DAT_1000_cae8 = 1;
              DAT_1000_f302 = 1;
              return;
            }
            if (DAT_1000_f302 == 1) {
              func_0x00016c68(uVar5,0x16f);
              _DAT_1000_cae8 = 1;
              DAT_1000_f302 = 0;
              return;
            }
            if ((_DAT_1000_be5c == 0x41) && (DAT_1000_f302 == 2)) {
              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x144,uVar5);
              func_0x0000f86c(0x2a97);
              _DAT_1000_cae8 = 1;
              return;
            }
          }
          if ((_DAT_1000_cac2 == 0x36) && ((_DAT_1000_be5c == 0x45 || (_DAT_1000_be5c == 0x49)))) {
            _DAT_1000_cac2 = 3;
          }
          if (((_DAT_1000_cac2 == 3) || (_DAT_1000_cac2 == 0x39)) && (_DAT_1000_be5c == 0x80)) {
            if (DAT_1000_f2b8 == '\0') {
              func_0x00016c68(uVar5,0x269);
            }
            else {
              func_0x00016c68(uVar5,0x140a);
            }
            _DAT_1000_cae8 = 1;
          }
          else if (((_DAT_1000_cac2 == 0x13) || (_DAT_1000_cac2 == 0x66)) &&
                  ((_DAT_1000_be5c == 0x8b && ((_DAT_1000_be5e == 0x60 && (DAT_1000_f307 == '\0'))))
                  )) {
            DAT_1000_f307 = '\x01';
            func_0x00016c68(uVar5,0x2da);
            _DAT_1000_cae8 = 1;
          }
          else if (DAT_1000_f307 == '\x01') {
            if (_DAT_1000_cac2 == 0x43) {
              _DAT_1000_cae8 = 1;
              DAT_1000_f307 = '\x02';
              func_0x00016c68(uVar5,0x2dc);
              _DAT_1000_45b4 = 0;
            }
            else {
              DAT_1000_f307 = '\0';
              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x162,uVar5);
              func_0x0000f86c(0x2a97);
              _DAT_1000_cae8 = 1;
            }
          }
          else {
            if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x91)) {
              func_0x00016c68(uVar5,0x27e);
              _DAT_1000_cae8 = 1;
              if (DAT_1000_f309 == '\0') {
                uVar5 = 0xc89;
                func_0x00016c68(0xc89,0x280);
              }
              else {
                uVar5 = 0xc89;
                func_0x00016c68(0xc89,0x281);
              }
            }
            if (((_DAT_1000_cac2 == 0x30) || (_DAT_1000_cac2 == 0x7c)) &&
               (((_DAT_1000_be5c == 0x1f && (_DAT_1000_be5e == 0x18d)) ||
                ((_DAT_1000_be5c == 0x18d && (_DAT_1000_be5e == 0x1f)))))) {
              if ((DAT_1000_5e03 == '\0') && (DAT_1000_5f71 == '\0')) {
                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x177,uVar5);
                func_0x0000f86c(0x2a97);
                _DAT_1000_cae8 = 1;
                return;
              }
              if (DAT_1000_5e03 == '\0') {
                DAT_1000_5e03 = 1;
                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,400,uVar5);
                func_0x0000f86c(0x2a97);
                DAT_1000_37f9 = 1;
                _DAT_1000_be5c = 0;
                _DAT_1000_cac2 = 3;
                return;
              }
              if (DAT_1000_5f71 == '\0') {
                if (DAT_1000_f331 == '\0') {
                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x1a8,uVar5);
                  _DAT_1000_cae8 = 1;
                  func_0x0000f86c(0x2a97);
                  return;
                }
                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x1ca,uVar5);
                func_0x0000f86c(0x2a97);
                DAT_1000_37f9 = 1;
                DAT_1000_5f71 = 1;
                _DAT_1000_be5c = 0;
                _DAT_1000_cac2 = 3;
                _DAT_1000_cae8 = 1;
                return;
              }
            }
            if (((_DAT_1000_cac2 == 0x30) && (_DAT_1000_be5c == 0x1f)) && (DAT_1000_f309 == '\x02'))
            {
              func_0x00016c68(uVar5,0xc4);
              _DAT_1000_cae8 = 1;
              DAT_1000_5e03 = '\x01';
              DAT_1000_37f9 = 1;
            }
            else {
              if (((_DAT_1000_cac2 == 0x30) || (_DAT_1000_cac2 == 0x7c)) && (_DAT_1000_be5e == 0x91)
                 ) {
                _DAT_1000_be5e = _DAT_1000_be5c;
                _DAT_1000_be5c = 0x91;
              }
              if (((_DAT_1000_cac2 == 0x30) || (_DAT_1000_cac2 == 0x7c)) &&
                 ((_DAT_1000_be5c == 0x91 && (_DAT_1000_be5e != 0)))) {
                if (DAT_1000_f309 == '\x02') {
                  if (_DAT_1000_be5e == 0x1f) {
                    func_0x00016c68(uVar5,0xc4);
                    _DAT_1000_cae8 = 1;
                    DAT_1000_5e03 = '\x01';
                    DAT_1000_37f9 = 1;
                  }
                  else if (_DAT_1000_be5e == 0x18d) {
                    if (DAT_1000_f331 == '\0') {
                      func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x1a8,uVar5);
                      _DAT_1000_cae8 = 1;
                      func_0x0000f86c(0x2a97);
                    }
                    else {
                      func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x1ca,uVar5);
                      func_0x0000f86c(0x2a97);
                      _DAT_1000_cae8 = 1;
                      DAT_1000_5f71 = '\x01';
                      DAT_1000_37f9 = 1;
                    }
                  }
                  else {
                    func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x206,uVar5);
                    func_0x0000f86c(0x2a97);
                    _DAT_1000_cae8 = 1;
                  }
                }
                else {
                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x1e3,uVar5);
                  func_0x0000f86c(0x2a97);
                  _DAT_1000_cae8 = 1;
                }
              }
              else {
                if ((((_DAT_1000_cac2 == 0x30) || (_DAT_1000_cac2 == 0x7c)) &&
                    (_DAT_1000_be5c == 0x91)) && (_DAT_1000_be5e == 0)) {
                  if (DAT_1000_f309 == '\x01') {
                    func_0x00016c68(uVar5,0x287);
                    _DAT_1000_cae8 = 1;
                    DAT_1000_f309 = 2;
                    return;
                  }
                  if (DAT_1000_f309 == '\0') {
                    func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x223,uVar5);
                    func_0x0000f86c(0x2a97);
                    _DAT_1000_cae8 = 1;
                    return;
                  }
                }
                if (DAT_1000_f309 == '\x02') {
                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x23b,uVar5);
                  uVar5 = 0xc89;
                  func_0x0000f86c(0x2a97);
                  DAT_1000_f309 = '\x01';
                }
                if ((_DAT_1000_cac2 == 0x3e) && (_DAT_1000_be5e == 0x91)) {
                  _DAT_1000_be5e = _DAT_1000_be5c;
                  _DAT_1000_be5c = 0x91;
                }
                if (((_DAT_1000_cac2 == 0x3e) && (_DAT_1000_be5c == 0x91)) &&
                   ((_DAT_1000_be5e == 0xb2 || (_DAT_1000_be5e == 0x93)))) {
                  if (DAT_1000_5e96 == '\x01') {
                    func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x25b,uVar5);
                    func_0x0000f86c(0x2a97);
                    _DAT_1000_cae8 = 1;
                  }
                  else if (DAT_1000_f30a == '\0') {
                    func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x277,uVar5);
                    func_0x0000f86c(0x2a97);
                    _DAT_1000_cae8 = 1;
                  }
                  else {
                    func_0x00016c68(uVar5,0x284);
                    _DAT_1000_cae8 = 1;
                    DAT_1000_f30a = DAT_1000_f30a + -1;
                    DAT_1000_f309 = '\x01';
                  }
                }
                else {
                  if ((_DAT_1000_cac2 == 0x3e) && (_DAT_1000_be5e == 0x18d)) {
                    _DAT_1000_be5e = _DAT_1000_be5c;
                    _DAT_1000_be5c = 0x18d;
                  }
                  if (((_DAT_1000_cac2 == 0x3e) && (_DAT_1000_be5c == 0x18d)) &&
                     ((_DAT_1000_be5e == 0xb2 || (_DAT_1000_be5e == 0x93)))) {
                    if (DAT_1000_5e96 == '\x01') {
                      func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x25b,uVar5);
                      func_0x0000f86c(0x2a97);
                      _DAT_1000_cae8 = 1;
                    }
                    else if (DAT_1000_f30a == '\0') {
                      func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x277,uVar5);
                      func_0x0000f86c(0x2a97);
                      _DAT_1000_cae8 = 1;
                    }
                    else {
                      func_0x00016c68(uVar5,0x62b);
                      _DAT_1000_cae8 = 1;
                      DAT_1000_f30a = DAT_1000_f30a + -1;
                      DAT_1000_f331 = '\x01';
                    }
                  }
                  else {
                    if (DAT_1000_f30a == '\0') {
                      DAT_1000_f30a = '\0';
                    }
                    if ((_DAT_1000_cac2 == 0x50) && (_DAT_1000_be5c == 0x1f)) {
                      func_0x00016c68(uVar5,0xc5);
                      DAT_1000_5e03 = '\0';
                      DAT_1000_37f9 = 0;
                      _DAT_1000_cae8 = 1;
                    }
                    else if ((_DAT_1000_cac2 == 0x50) && (_DAT_1000_be5c == 0x18d)) {
                      func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x290,uVar5);
                      func_0x0000f86c(0x2a97);
                      DAT_1000_5f71 = '\0';
                      _DAT_1000_cae8 = 1;
                      DAT_1000_37f9 = 0;
                    }
                    else if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0xb2)) {
                      if (DAT_1000_f30a == '\0') {
                        func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x2b1,uVar5);
                        func_0x0000f86c(0x2a97);
                        _DAT_1000_cae8 = 1;
                      }
                      else {
                        func_0x00016c68(uVar5,_DAT_1000_723c);
                        _DAT_1000_cae8 = 1;
                      }
                    }
                    else {
                      if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x17d)) {
                        func_0x00016c68(uVar5,0x600);
                        if (DAT_1000_5f66 == '\0') {
                          func_0x00016c68(0xc89,0x602);
                        }
                        uVar5 = 0xc89;
                        _DAT_1000_cae8 = 1;
                      }
                      if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x18d)) {
                        func_0x00016c68(uVar5,_DAT_1000_73f2);
                        _DAT_1000_cae8 = 1;
                        if (DAT_1000_f331 == '\0') {
                          func_0x00016c68(0xc89,0x629);
                        }
                        else {
                          func_0x00016c68(0xc89,0x62a);
                        }
                        if (DAT_1000_5f71 == '\0') {
                          func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x2c7,0xc89);
                        }
                        else {
                          func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x2e0,0xc89);
                        }
                        _DAT_1000_cae8 = 1;
                        func_0x0000f86c(0x2a97);
                      }
                      else if ((_DAT_1000_cac2 == 3) &&
                              ((_DAT_1000_be5c == 0xbf && (DAT_1000_f30b == '\0')))) {
                        DAT_1000_f30b = '\x01';
                        func_0x00016c68(uVar5,0x306);
                        _DAT_1000_cae8 = 1;
                      }
                      else if ((_DAT_1000_cac2 == 2) && (_DAT_1000_be5c == 0xbf)) {
                        if (DAT_1000_f30c == '\0') {
                          func_0x00016c68(uVar5,0x30a);
                          _DAT_1000_cae8 = 1;
                          DAT_1000_f30c = '\x01';
                        }
                        else {
                          func_0x00016c68(uVar5,0x310);
                          _DAT_1000_cae8 = 1;
                        }
                      }
                      else if (((_DAT_1000_cac2 == 0x20) || (_DAT_1000_cac2 == 0x38)) &&
                              ((_DAT_1000_be5c == 0xe1 || (_DAT_1000_be5e == 0xe1)))) {
                        func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x317,uVar5);
                        func_0x0000f86c(0x2a97);
                        _DAT_1000_cae8 = 1;
                      }
                      else if (((_DAT_1000_cac2 == 0x20) || (_DAT_1000_cac2 == 0x38)) &&
                              (((0xe7 < _DAT_1000_be5c && (_DAT_1000_be5c < 0xed)) ||
                               ((0xe7 < _DAT_1000_be5e && (_DAT_1000_be5e < 0xed)))))) {
                        func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x317,uVar5);
                        func_0x0000f86c(0x2a97);
                        _DAT_1000_cae8 = 1;
                      }
                      else if ((_DAT_1000_cac2 == 0x7d) &&
                              ((_DAT_1000_be5c == 0xe1 && (DAT_1000_f316 != '\x03')))) {
                        func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x367,uVar5);
                        func_0x0000f86c(0x2a97);
                        _DAT_1000_cae8 = 1;
                      }
                      else {
                        if ((_DAT_1000_cac2 == 0x7d) && (_DAT_1000_be5c == 0xe1)) {
                          if (_DAT_1000_be5e == 0) {
                            if (DAT_1000_f318 == '\0') {
                              _DAT_1000_466c = 0xffff;
                              DAT_1000_5227 = 1;
                              _DAT_1000_729a = 0x378;
                              _DAT_1000_cae8 = 1;
                              DAT_1000_f318 = 1;
                              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x394,uVar5);
                              func_0x0000f86c(0x2a97);
                              return;
                            }
                            if (DAT_1000_f318 == '\x01') {
                              _DAT_1000_4668 = 0xffff;
                              DAT_1000_5225 = 1;
                              _DAT_1000_466a = 0xffff;
                              DAT_1000_5226 = 1;
                              _DAT_1000_4660 = 4;
                              DAT_1000_5221 = 3;
                              _DAT_1000_729a = 0x363;
                              DAT_1000_f318 = 2;
                              _DAT_1000_cae8 = 1;
                              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x3c8,uVar5);
                              func_0x0000f86c(0x2a97);
                              return;
                            }
                            if (DAT_1000_f318 == '\x03') {
                              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x3c8,uVar5);
                              func_0x0000f86c(0x2a97);
                              _DAT_1000_4660 = 4;
                              _DAT_1000_466a = 0xffff;
                              _DAT_1000_466c = 0xffff;
                              DAT_1000_5221 = 3;
                              DAT_1000_5226 = 1;
                              DAT_1000_5227 = 1;
                              _DAT_1000_729a = 0x363;
                              _DAT_1000_cae8 = 1;
                              DAT_1000_f318 = 2;
                              return;
                            }
                          }
                          else {
                            if (_DAT_1000_be5e == 0xe7) {
                              if ((DAT_1000_f318 == '\x01') || (DAT_1000_f318 == '\x02')) {
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x3f1,uVar5);
                                func_0x0000f86c(0x2a97);
                                _DAT_1000_cae8 = 1;
                                return;
                              }
                              if (DAT_1000_f318 == '\x03') {
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x3c8,uVar5);
                                func_0x0000f86c(0x2a97);
                                _DAT_1000_4660 = 4;
                                _DAT_1000_466a = 0xffff;
                                _DAT_1000_466c = 0xffff;
                                DAT_1000_5221 = 3;
                                DAT_1000_5226 = 1;
                                DAT_1000_5227 = 1;
                                _DAT_1000_729a = 0x363;
                                _DAT_1000_cae8 = 1;
                                DAT_1000_f318 = 2;
                                return;
                              }
                              if (DAT_1000_f318 == '\0') {
                                _DAT_1000_466c = 0xffff;
                                DAT_1000_5227 = 1;
                                _DAT_1000_729a = 0x378;
                                _DAT_1000_cae8 = 1;
                                DAT_1000_f318 = 1;
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x394,uVar5);
                                func_0x0000f86c(0x2a97);
                                return;
                              }
                            }
                            if (_DAT_1000_be5e == 0xe5) {
                              if ((DAT_1000_f318 == '\x02') || (DAT_1000_f318 == '\x03')) {
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x416,uVar5);
                                func_0x0000f86c(0x2a97);
                                _DAT_1000_cae8 = 1;
                                return;
                              }
                              if (DAT_1000_f318 == '\x01') {
                                _DAT_1000_4668 = 0xffff;
                                DAT_1000_5225 = 1;
                                _DAT_1000_466a = 0xffff;
                                DAT_1000_5226 = 1;
                                _DAT_1000_4660 = 4;
                                DAT_1000_5221 = 3;
                                _DAT_1000_729a = 0x363;
                                DAT_1000_f318 = 2;
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x3c8,uVar5);
                                func_0x0000f86c(0x2a97);
                                _DAT_1000_cae8 = 1;
                                return;
                              }
                              if (DAT_1000_f318 == '\0') {
                                _DAT_1000_4668 = 0xffff;
                                DAT_1000_5225 = 1;
                                _DAT_1000_729a = 0x37b;
                                _DAT_1000_cae8 = 1;
                                DAT_1000_f318 = 3;
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x43a,uVar5);
                                func_0x0000f86c(0x2a97);
                                return;
                              }
                            }
                            if (_DAT_1000_be5e == 0xe6) {
                              if (DAT_1000_f318 == '\0') {
                                _DAT_1000_4660 = 4;
                                DAT_1000_5221 = 3;
                                _DAT_1000_729a = 0x363;
                                _DAT_1000_4668 = 0xffff;
                                _DAT_1000_466c = 0xffff;
                                _DAT_1000_466a = 0xffff;
                                DAT_1000_5225 = 1;
                                DAT_1000_522f = 1;
                                DAT_1000_5227 = 1;
                                _DAT_1000_cae8 = 1;
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x45c,uVar5);
                                func_0x0000f86c(0x2a97);
                                DAT_1000_f318 = 2;
                                return;
                              }
                              if (DAT_1000_f318 == '\x01') {
                                _DAT_1000_4660 = 4;
                                DAT_1000_5221 = 3;
                                _DAT_1000_729a = 0x363;
                                _DAT_1000_4668 = 0xffff;
                                _DAT_1000_466a = 0xffff;
                                DAT_1000_5225 = 1;
                                DAT_1000_5226 = 1;
                                _DAT_1000_cae8 = 1;
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x45c,uVar5);
                                func_0x0000f86c(0x2a97);
                                DAT_1000_f318 = 2;
                                return;
                              }
                              if (DAT_1000_f318 == '\x03') {
                                _DAT_1000_4660 = 4;
                                DAT_1000_5221 = 3;
                                _DAT_1000_729a = 0x363;
                                _DAT_1000_466a = 0xffff;
                                DAT_1000_5226 = 1;
                                _DAT_1000_466c = 0xffff;
                                DAT_1000_5227 = 1;
                                _DAT_1000_cae8 = 1;
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x45c,uVar5);
                                func_0x0000f86c(0x2a97);
                                DAT_1000_f318 = 2;
                                return;
                              }
                            }
                          }
                        }
                        if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5e == 0xe5)) {
                          _DAT_1000_be5e = _DAT_1000_be5c;
                          _DAT_1000_be5c = 0xe5;
                        }
                        if (((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0xe5)) &&
                           (DAT_1000_5225 != '\x01')) {
                          func_0x00016c68(uVar5,0x396);
                          _DAT_1000_cae8 = 1;
                        }
                        else if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0xe5)) {
                          if (*(char *)(_DAT_1000_be5e + 0x5140) != '\x01') {
                            func_0x00016c68(uVar5,0x707);
                            _DAT_1000_cae8 = 1;
                            return;
                          }
                          if (_DAT_1000_be5e == 0xe6) {
                            if (DAT_1000_f318 == '\x02') {
                              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x48c,uVar5);
                              func_0x0000f86c(0x2a97);
                              _DAT_1000_4660 = 0xffff;
                              _DAT_1000_4668 = (uint)DAT_1000_be1b;
                              _DAT_1000_466a = (uint)DAT_1000_be1b;
                              DAT_1000_5221 = 1;
                              DAT_1000_5225 = 3;
                              DAT_1000_5226 = 3;
                              _DAT_1000_729a = 0x378;
                              _DAT_1000_cae8 = 1;
                              DAT_1000_f318 = 1;
                              return;
                            }
                            if (DAT_1000_f318 == '\x03') {
                              func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x4c4,uVar5);
                              func_0x0000f86c(0x2a97);
                              _DAT_1000_4668 = (uint)DAT_1000_be1b;
                              DAT_1000_5225 = 3;
                              _DAT_1000_729a = 0x375;
                              _DAT_1000_cae8 = 1;
                              DAT_1000_f318 = 0;
                              return;
                            }
                          }
                          if ((_DAT_1000_be5e == 0xe1) && (DAT_1000_f318 == '\x03')) {
                            func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x4c4,uVar5);
                            func_0x0000f86c(0x2a97);
                            _DAT_1000_cae8 = 1;
                            _DAT_1000_729a = 0x375;
                            DAT_1000_f318 = '\0';
                            _DAT_1000_4668 = (uint)DAT_1000_be1b;
                            DAT_1000_5225 = '\x03';
                          }
                          else if (_DAT_1000_be5e == 0x62) {
                            func_0x00016c68(uVar5,0x37e);
                            _DAT_1000_455e = 0xffff;
                            DAT_1000_51a0 = 1;
                            _DAT_1000_4668 = (uint)DAT_1000_be1b;
                            DAT_1000_5225 = '\x03';
                            _DAT_1000_4562 = (uint)DAT_1000_be1b;
                            DAT_1000_51a2 = 3;
                            _DAT_1000_7198 = 0x37e;
                            _DAT_1000_cae8 = 1;
                          }
                          else if (_DAT_1000_be5e == 0xe8) {
                            _DAT_1000_4668 = (uint)DAT_1000_be1b;
                            DAT_1000_5225 = '\x03';
                            _DAT_1000_466e = 0;
                            DAT_1000_5228 = '\x01';
                            _DAT_1000_4676 = 0xffff;
                            DAT_1000_522c = 1;
                            func_0x00016c68(uVar5,0x385);
                            _DAT_1000_cae8 = 1;
                          }
                          else {
                            func_0x00016c68(uVar5,0x39f);
                            _DAT_1000_cae8 = 1;
                          }
                        }
                        else {
                          if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5e == 0xe6)) {
                            _DAT_1000_be5e = _DAT_1000_be5c;
                            _DAT_1000_be5c = 0xe6;
                          }
                          if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0xe6)) {
                            if ((*(char *)(_DAT_1000_be5e + 0x5140) == '\x01') &&
                               (DAT_1000_5226 == '\x01')) {
                              if (_DAT_1000_be5e == 0x100) {
                                func_0x00016c68(uVar5,0x382);
                                _DAT_1000_cae8 = 1;
                                _DAT_1000_469e = (uint)DAT_1000_be1b;
                                DAT_1000_5240 = '\x03';
                                _DAT_1000_466a = (uint)DAT_1000_be1b;
                                DAT_1000_5226 = '\x03';
                                _DAT_1000_466e = 0xffff;
                                DAT_1000_5228 = '\x01';
                                _DAT_1000_72a8 = 0x382;
                              }
                              else if (_DAT_1000_be5e == 0xe7) {
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x4ed,uVar5);
                                func_0x0002af9a(0x2a97,0xcaea,0x1000,local_102,0x1000);
                                func_0x0002b027(0x2a97,0x52a,0x2a97);
                                func_0x0002afb4(0x2a97,0xff,0xcaea,0x1000);
                                func_0x0000f86c(0x2a97);
                                _DAT_1000_cae8 = 1;
                              }
                              else {
                                func_0x00016c68(uVar5,0x39f);
                                _DAT_1000_cae8 = 1;
                              }
                            }
                            else {
                              func_0x00016c68(uVar5,0x707);
                              _DAT_1000_cae8 = 1;
                            }
                          }
                          else {
                            if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5e == 0xe7)) {
                              _DAT_1000_be5e = _DAT_1000_be5c;
                              _DAT_1000_be5c = 0xe7;
                            }
                            if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0xe7)) {
                              if ((*(char *)(_DAT_1000_be5e + 0x5140) == '\x01') &&
                                 (DAT_1000_5227 == '\x01')) {
                                if (_DAT_1000_be5e == 0xe1) {
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x564,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_cae8 = 1;
                                  DAT_1000_f318 = '\0';
                                  _DAT_1000_466c = (uint)DAT_1000_be1b;
                                  DAT_1000_5227 = '\x03';
                                  _DAT_1000_729a = 0x375;
                                }
                                else {
                                  func_0x00016c68(uVar5,0x39f);
                                  _DAT_1000_cae8 = 1;
                                }
                              }
                              else {
                                func_0x00016c68(uVar5,0x707);
                                _DAT_1000_cae8 = 1;
                              }
                            }
                            else {
                              if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5e == 0xe8)) {
                                _DAT_1000_be5e = _DAT_1000_be5c;
                                _DAT_1000_be5c = 0xe8;
                              }
                              if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0xe8)) {
                                if ((*(char *)(_DAT_1000_be5e + 0x5140) != '\x01') ||
                                   (DAT_1000_5228 != '\x01')) {
                                  func_0x00016c68(uVar5,0x707);
                                  _DAT_1000_cae8 = 1;
                                  return;
                                }
                                if (_DAT_1000_be5e == 0x1d) {
                                  func_0x00016c68(uVar5,0x388);
                                  _DAT_1000_44d8 = (uint)DAT_1000_be1b;
                                  _DAT_1000_466e = 0;
                                  _DAT_1000_4670 = 0xffff;
                                  DAT_1000_515d = 3;
                                  DAT_1000_5228 = 3;
                                  DAT_1000_5229 = 1;
                                  _DAT_1000_72aa = 0x388;
                                  _DAT_1000_cae8 = 1;
                                  return;
                                }
                              }
                              if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5e == 0x100)) {
                                _DAT_1000_be5e = _DAT_1000_be5c;
                                _DAT_1000_be5c = 0x100;
                              }
                              if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0x100)) {
                                if ((*(char *)(_DAT_1000_be5e + 0x5140) != '\x01') ||
                                   (DAT_1000_5240 != '\x01')) {
                                  func_0x00016c68(uVar5,0x707);
                                  _DAT_1000_cae8 = 1;
                                  return;
                                }
                                if ((_DAT_1000_be5e == 0xe1) && (DAT_1000_f318 == '\x01')) {
                                  func_0x00016c68(uVar5,0x385);
                                  _DAT_1000_4660 = 0;
                                  _DAT_1000_4676 = 0xffff;
                                  _DAT_1000_469e = 0;
                                  DAT_1000_5221 = 3;
                                  DAT_1000_522c = 3;
                                  DAT_1000_5240 = 3;
                                  _DAT_1000_72b0 = 0x385;
                                  _DAT_1000_cae8 = 1;
                                  return;
                                }
                              }
                              if (_DAT_1000_cac2 == 0x7d) {
                                if (_DAT_1000_be5c == 0xe8) {
                                  _DAT_1000_466e = 0;
                                  DAT_1000_5228 = '\x03';
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x58e,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_cae8 = 1;
                                  _DAT_1000_466a = 0xffff;
                                  DAT_1000_5226 = '\x01';
                                  _DAT_1000_469e = 0xffff;
                                  DAT_1000_5240 = '\x01';
                                }
                                else if (_DAT_1000_be5c == 0xec) {
                                  _DAT_1000_4676 = 0;
                                  DAT_1000_522c = 3;
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x5b7,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_466a = 0xffff;
                                  DAT_1000_5226 = '\x01';
                                  _DAT_1000_4668 = 0xffff;
                                  DAT_1000_5225 = '\x01';
                                  _DAT_1000_469e = 0xffff;
                                  DAT_1000_5240 = '\x01';
                                  _DAT_1000_cae8 = 1;
                                }
                                else if (_DAT_1000_be5c == 0xe9) {
                                  _DAT_1000_4670 = 0;
                                  DAT_1000_5229 = 3;
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x5e1,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_cae8 = 1;
                                  _DAT_1000_466a = 0xffff;
                                  DAT_1000_5226 = '\x01';
                                  _DAT_1000_469e = 0xffff;
                                  DAT_1000_5240 = '\x01';
                                  _DAT_1000_44d8 = 0xffff;
                                  DAT_1000_515d = 1;
                                }
                                else if (_DAT_1000_be5c == 0xea) {
                                  _DAT_1000_4672 = 0;
                                  DAT_1000_522a = 3;
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x609,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  DAT_1000_f318 = '\0';
                                  _DAT_1000_4660 = 0xffff;
                                  DAT_1000_5221 = 1;
                                  _DAT_1000_44d8 = 0xffff;
                                  DAT_1000_515d = 1;
                                  _DAT_1000_cae8 = 1;
                                }
                                else if (_DAT_1000_be5c == 0x60) {
                                  _DAT_1000_455e = 0;
                                  DAT_1000_51a0 = 0;
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x631,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_4668 = 0xffff;
                                  DAT_1000_5225 = '\x01';
                                  DAT_1000_51a2 = 1;
                                  _DAT_1000_4562 = 0xffff;
                                  _DAT_1000_cae8 = 1;
                                }
                                else if (_DAT_1000_be5e == 0xe8) {
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x58e,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_466e = 0;
                                  DAT_1000_5228 = '\x03';
                                  _DAT_1000_4668 = 0xffff;
                                  _DAT_1000_469e = 0xffff;
                                  DAT_1000_5240 = '\x01';
                                  DAT_1000_5225 = '\x01';
                                  _DAT_1000_cae8 = 1;
                                }
                                else {
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x657,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_cae8 = 1;
                                }
                              }
                              else if (((_DAT_1000_cac2 == 7) && (_DAT_1000_be5c == 0x111)) &&
                                      (DAT_1000_be1b == uRam000146c0)) {
                                DAT_1000_f31c = '\x01';
                                func_0x00016c68(uVar5,0x435);
                                _DAT_1000_cae8 = 1;
                              }
                              else if (((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0)) &&
                                      (DAT_1000_f31c == '\x01')) {
                                func_0x00016c68(uVar5,0x435);
                                _DAT_1000_cae8 = 1;
                              }
                              else if ((DAT_1000_f32c == '\x01') && (DAT_1000_f31c == '\x01')) {
                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x674,uVar5);
                                func_0x0000f86c(0x2a97);
                                func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x6b5,0xc89);
                                func_0x0000f86c(0x2a97);
                                _DAT_1000_cae8 = 1;
                              }
                              else if ((_DAT_1000_cac2 == 7) && (DAT_1000_f31c == '\x01')) {
                                if (_DAT_1000_be5c == 7) {
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x6ec,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_cae8 = 1;
                                }
                                else {
                                  DAT_1000_f31c = '\0';
                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x6c8,uVar5);
                                  func_0x0000f86c(0x2a97);
                                  _DAT_1000_cae8 = 1;
                                }
                              }
                              else {
                                if (((((_DAT_1000_cac2 == 0x3e) || (_DAT_1000_cac2 == 0x1d)) ||
                                     (_DAT_1000_cac2 == 0x1f)) || (_DAT_1000_cac2 == 0x7a)) &&
                                   ((_DAT_1000_be5e == 0x81 && (_DAT_1000_be5c == 0x82)))) {
                                  _DAT_1000_be5c = 0x81;
                                  _DAT_1000_be5e = 0x82;
                                }
                                if ((((_DAT_1000_cac2 == 0x3e) || (_DAT_1000_cac2 == 0x1d)) ||
                                    ((_DAT_1000_cac2 == 0x1f || (_DAT_1000_cac2 == 0x7a)))) &&
                                   ((_DAT_1000_be5c == 0x81 && (_DAT_1000_be5e == 0x82)))) {
                                  if (DAT_1000_f304 == '\0') {
                                    func_0x00016c68(uVar5,0x549);
                                    DAT_1000_f304 = '\x01';
                                    DAT_1000_f326 = DAT_1000_f322;
                                    _DAT_1000_cae8 = 1;
                                    _DAT_1000_735a = 0x548;
                                    _DAT_1000_45a0 = 0;
                                    DAT_1000_51c1 = 3;
                                  }
                                  else {
                                    func_0x00016c68(uVar5,0x548);
                                    _DAT_1000_cae8 = 1;
                                  }
                                }
                                else if (((_DAT_1000_cac2 == 0x81) || (_DAT_1000_cac2 == 0x38)) &&
                                        (_DAT_1000_be5c == 0x82)) {
                                  if (DAT_1000_51c2 == '\x01') {
                                    if (DAT_1000_f304 == '\0') {
                                      DAT_1000_f322 = DAT_1000_f322 == '\0';
                                      func_0x00016c68(uVar5,0x4b7);
                                      _DAT_1000_cae8 = 1;
                                    }
                                    else {
                                      DAT_1000_f322 = DAT_1000_f322 == '\0';
                                      func_0x00016c68(uVar5,0x4ba);
                                      _DAT_1000_cae8 = 1;
                                    }
                                  }
                                  else {
                                    func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x72b,uVar5);
                                    func_0x0000f86c(0x2a97);
                                    _DAT_1000_cae8 = 1;
                                  }
                                }
                                else if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x82)) {
                                  if (DAT_1000_f304 == '\0') {
                                    func_0x00016c68(uVar5,0x4ac);
                                    if (DAT_1000_f322 == '\x01') {
                                      func_0x00016c68(0xc89,0x4b5);
                                    }
                                    _DAT_1000_cae8 = 1;
                                  }
                                  else if (DAT_1000_f322 == '\x01') {
                                    if (DAT_1000_f326 == '\x01') {
                                      func_0x00016c68(uVar5,0x4b0);
                                      func_0x00016c68(0xc89,0x4b5);
                                      _DAT_1000_cae8 = 1;
                                    }
                                    else {
                                      func_0x00016c68(uVar5,0x4ac);
                                      func_0x00016c68(0xc89,0x4b5);
                                      _DAT_1000_cae8 = 1;
                                    }
                                  }
                                  else if (DAT_1000_f322 == DAT_1000_f326) {
                                    func_0x00016c68(uVar5,0x4b0);
                                    _DAT_1000_cae8 = 1;
                                  }
                                  else {
                                    func_0x00016c68(uVar5,0x4ac);
                                    _DAT_1000_cae8 = 1;
                                  }
                                }
                                else if (_DAT_1000_be5c == 0x133) {
                                  func_0x00016c68(uVar5,0x4c0);
                                  _DAT_1000_cae8 = 1;
                                }
                                else if ((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x111)) {
                                  func_0x00016c68(uVar5,0x520);
                                  _DAT_1000_cae8 = 1;
                                }
                                else if ((_DAT_1000_cac2 == 3) &&
                                        ((_DAT_1000_be5c == 0x111 && (_DAT_1000_3a70 == 0x175)))) {
                                  func_0x00016c68(uVar5,0x53d);
                                  func_0x00016c68(0xc89,0x53f);
                                  _DAT_1000_cae8 = 1;
                                }
                                else {
                                  if ((_DAT_1000_cac2 == 1) &&
                                     ((_DAT_1000_be5c == 0x13a && (_DAT_1000_3a70 == 0x175)))) {
                                    DAT_1000_527a = 2;
                                    _DAT_1000_3a70 = 2;
                                    _DAT_1000_66aa = 0x706;
                                  }
                                  if (((_DAT_1000_cac2 == 2) && (_DAT_1000_be5e == 0x13a)) &&
                                     (_DAT_1000_be5c == 0x111)) {
                                    _DAT_1000_be5c = 0x111;
                                  }
                                  if (((_DAT_1000_cac2 == 2) && (_DAT_1000_be5c == 0x13a)) &&
                                     (_DAT_1000_be5e == 0x111)) {
                                    func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x756,uVar5);
                                    func_0x0000f86c(0x2a97);
                                    _DAT_1000_cae8 = 1;
                                    _DAT_1000_3a70 = 0x175;
                                    _DAT_1000_66aa = 0;
                                    _DAT_1000_4712 = (uint)DAT_1000_be1b;
                                  }
                                  else {
                                    uVar6 = uVar5;
                                    if ((_DAT_1000_cac2 == 4) && (_DAT_1000_be5c == 0x13a)) {
                                      uVar6 = 0xc89;
                                      func_0x00016c68(uVar5,0x54f);
                                    }
                                    if (((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x143)) &&
                                       (DAT_1000_f2f7 == '\x01')) {
                                      if (DAT_1000_f31c == '\x01') {
                                        func_0x00016c68(uVar6,0x536);
                                        _DAT_1000_66bc = 0;
                                        DAT_1000_5283 = 1;
                                        _DAT_1000_4724 = 0xffff;
                                        DAT_1000_f2f7 = '\0';
                                        _DAT_1000_cae8 = 1;
                                      }
                                      else {
                                        func_0x00016c68(uVar6,0x535);
                                        _DAT_1000_cae8 = 1;
                                      }
                                    }
                                    else if ((_DAT_1000_cac2 == 0x1f) && (_DAT_1000_be5c == 0x143))
                                    {
                                      if (DAT_1000_f31c == '\x01') {
                                        _DAT_1000_4724 = (uint)DAT_1000_be1b;
                                        _DAT_1000_66bc = 0x53b;
                                        DAT_1000_5283 = 3;
                                        DAT_1000_f2f7 = '\x01';
                                        func_0x00016c68(uVar6,0x53a);
                                        _DAT_1000_cae8 = 1;
                                      }
                                      else {
                                        func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0x785,uVar6);
                                        func_0x0000f86c(0x2a97);
                                        _DAT_1000_cae8 = 1;
                                      }
                                    }
                                    else if ((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x61)) {
                                      DAT_1000_51a1 = 1;
                                      _DAT_1000_38be = 0;
                                      func_0x00016c68(uVar6,0x572);
                                      _DAT_1000_7370 = 0x571;
                                    }
                                    else {
                                      if (_DAT_1000_45c4 == -0xb2) {
                                        _DAT_1000_723c = 0x5e3;
                                      }
                                      else {
                                        _DAT_1000_723c = 0x5e6;
                                      }
                                      if ((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x93)) {
                                        func_0x0002afb4(uVar6,0xff,0xcaea,0x1000,0x7af,uVar6);
                                        func_0x0000f86c(0x2a97);
                                        _DAT_1000_cae8 = 1;
                                      }
                                      else if (((_DAT_1000_cac2 == 0x6f) ||
                                               ((_DAT_1000_cac2 == 0x49 || (_DAT_1000_cac2 == 0x37))
                                               )) && (_DAT_1000_be5c == 0x111)) {
                                        func_0x00016c68(uVar6,0x528);
                                        _DAT_1000_cae8 = 1;
                                      }
                                      else if ((_DAT_1000_cac2 == 7) &&
                                              (((_DAT_1000_be5c == 7 || (_DAT_1000_be5c == 8)) &&
                                               (DAT_1000_f32c == '\x01')))) {
                                        func_0x00016c68(uVar6,0x52d);
                                        _DAT_1000_cae8 = 1;
                                      }
                                      else if ((_DAT_1000_cac2 == 0x66) && (_DAT_1000_be5c == 0x62))
                                      {
                                        func_0x00016c68(uVar6,0x21a);
                                        _DAT_1000_cae8 = 1;
                                      }
                                      else {
                                        uVar5 = uVar6;
                                        if (DAT_1000_f32e == '\x01') {
                                          if (DAT_1000_5e33 == '\x01') {
                                            DAT_1000_f32f = DAT_1000_f32f + 1;
                                            if (DAT_1000_f32f == 1) {
                                              func_0x00016c68(uVar6,0x19c);
                                              uVar5 = 0xc89;
                                            }
                                            else if (DAT_1000_f32f == 2) {
                                              func_0x00016c68(uVar6,0x1a4);
                                              uVar5 = 0xc89;
                                            }
                                            else if (DAT_1000_f32f == 3) {
                                              uVar5 = 0xc89;
                                              func_0x00016c68(uVar6,0x1aa);
                                            }
                                            if (2 < DAT_1000_f32f) {
                                              DAT_1000_f32f = 0;
                                            }
                                            DAT_1000_f32e = '\0';
                                          }
                                          else {
                                            uVar5 = 0xc89;
                                            func_0x00016c68(uVar6,0x1b3);
                                            DAT_1000_f32e = '\x02';
                                            DAT_1000_f32d = 4;
                                          }
                                        }
                                        uVar4 = _DAT_1000_f336;
                                        uVar3 = _DAT_1000_f334;
                                        uVar2 = _DAT_1000_f332;
                                        uVar1 = _DAT_1000_46fe;
                                        if (((_DAT_1000_cac2 == 6) || (_DAT_1000_cac2 == 0x7a)) &&
                                           ((_DAT_1000_be5c == 0x67 && (_DAT_1000_be5e == 0x81)))) {
                                          if (_DAT_1000_be60 == 0x82) {
                                            func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x7d4,uVar5);
                                            func_0x0000f86c(0x2a97);
                                            func_0x00016c68(0xc89,0x249);
                                            _DAT_1000_71a6 = 0x24e;
                                            DAT_1000_f304 = '\x01';
                                            DAT_1000_f326 = DAT_1000_f322;
                                            _DAT_1000_735a = 0x548;
                                            _DAT_1000_45a0 = 0;
                                            DAT_1000_51c1 = 3;
                                            _DAT_1000_cae8 = 1;
                                          }
                                          else if (_DAT_1000_be60 == 0) {
                                            func_0x00016c68(uVar5,0x245);
                                            _DAT_1000_cae8 = 1;
                                          }
                                          else {
                                            func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x813,uVar5);
                                            func_0x0000f86c(0x2a97);
                                            _DAT_1000_cae8 = 1;
                                          }
                                        }
                                        else {
                                          _DAT_1000_f338 = _DAT_1000_f336;
                                          _DAT_1000_f336 = _DAT_1000_f334;
                                          _DAT_1000_f334 = _DAT_1000_f332;
                                          _DAT_1000_f332 = _DAT_1000_46fe;
                                          if (0 < (int)_DAT_1000_46fe) {
                                            _DAT_1000_7d7a = 1;
                                            while( true ) {
                                              if ((((0 < *(int *)(uVar1 * 0xe + _DAT_1000_7d7a * 2 +
                                                                 -0x52b0)) &&
                                                   (*(int *)(uVar1 * 0xe + _DAT_1000_7d7a * 2 +
                                                            -0x52b0) < 5)) ||
                                                  ((5 < *(int *)(uVar1 * 0xe + _DAT_1000_7d7a * 2 +
                                                                -0x52b0) &&
                                                   (*(int *)(uVar1 * 0xe + _DAT_1000_7d7a * 2 +
                                                            -0x52b0) < 0xc)))) &&
                                                 (((((((_DAT_1000_46fe != 0xfec6 &&
                                                       (DAT_1000_f33a != '\x01')) &&
                                                      (*(uint *)(uVar1 * 0xe + _DAT_1000_7d7a * 2 +
                                                                -0x52b0) != _DAT_1000_4724)) &&
                                                     ((_DAT_1000_4724 != 0xffff ||
                                                      ((uint)DAT_1000_be1b !=
                                                       *(uint *)(uVar1 * 0xe + _DAT_1000_7d7a * 2 +
                                                                -0x52b0))))) &&
                                                    (_DAT_1000_46fe =
                                                          *(uint *)(uVar1 * 0xe + _DAT_1000_7d7a * 2
                                                                   + -0x52b0),
                                                    _DAT_1000_46fe != uVar4)) &&
                                                   ((_DAT_1000_46fe != uVar3 &&
                                                    (_DAT_1000_46fe != uVar1)))) &&
                                                  (_DAT_1000_46fe != uVar2)))) {
                                                _DAT_1000_7d7a = 7;
                                              }
                                              if (_DAT_1000_7d7a == 7) break;
                                              _DAT_1000_7d7a = _DAT_1000_7d7a + 1;
                                            }
                                          }
                                          uVar6 = uVar5;
                                          if ((_DAT_1000_46fe == uVar1) &&
                                             (DAT_1000_be1b == _DAT_1000_46fe)) {
                                            uVar6 = 0xc89;
                                            func_0x00016c68(uVar5,0x4eb);
                                          }
                                          uVar5 = uVar6;
                                          if ((_DAT_1000_46fe != _DAT_1000_f332) &&
                                             (DAT_1000_be1b == _DAT_1000_f332)) {
                                            uVar5 = 0xc89;
                                            func_0x00016c68(uVar6,0x4e8);
                                          }
                                          if (6 < DAT_1000_f33b) {
                                            DAT_1000_f33b = 0;
                                          }
                                          if (DAT_1000_f33a == '\0') {
                                            DAT_1000_f33b = DAT_1000_f33b + 1;
                                          }
                                          uVar6 = uVar5;
                                          if ((DAT_1000_be1b == _DAT_1000_46fe) &&
                                             ((((DAT_1000_be1b == _DAT_1000_4712 ||
                                                ((_DAT_1000_4712 == 0xffff &&
                                                 (DAT_1000_be1b == _DAT_1000_46fe)))) &&
                                               (DAT_1000_5f1e == '\0')) &&
                                              ((DAT_1000_f33b == 3 || (DAT_1000_f33b == 2)))))) {
                                            if (_DAT_1000_476e == -0x13a) {
                                              uVar6 = 0xc89;
                                              func_0x00016c68(uVar5,0x710);
                                              _DAT_1000_46fe = 0xfec6;
                                            }
                                            else {
                                              uVar6 = 0xc89;
                                              func_0x00016c68(uVar5,0x70a);
                                              _DAT_1000_46fe = (uint)DAT_1000_be1b;
                                            }
                                          }
                                          if (_DAT_1000_46fe == 0xfec6) {
                                            _DAT_1000_4714 = (uint)DAT_1000_be1b;
                                            _DAT_1000_4716 = (uint)DAT_1000_be1b;
                                            _DAT_1000_4718 = (uint)DAT_1000_be1b;
                                            _DAT_1000_471c = (uint)DAT_1000_be1b;
                                          }
                                          if ((DAT_1000_f33b == 5) && (DAT_1000_f33a == '\0')) {
                                            if (_DAT_1000_46fe == 0xfec6) {
                                              if (DAT_1000_5f1e != '\0') {
                                                func_0x00016c68(uVar6,0x4f1);
                                                if (_DAT_1000_476e != -0x13a) {
                                                  return;
                                                }
                                                if (DAT_1000_f2ec == '\0') {
                                                  DAT_1000_f2ec = '\x01';
                                                  _DAT_1000_cae4 = _DAT_1000_cae4 + 10;
                                                }
                                                DAT_1000_f33a = 1;
                                                DAT_1000_5270 = 1;
                                                _DAT_1000_7338 = 0x714;
                                                _DAT_1000_734e = 0x500;
                                                _DAT_1000_7350 = 0x500;
                                                _DAT_1000_7352 = 0x500;
                                                _DAT_1000_7356 = 0x500;
                                                func_0x00016c68(0xc89,0x4f7);
                                                func_0x00016c68(0xc89,0x4f8);
                                                return;
                                              }
                                              func_0x00016c68(uVar6,0x4ef);
                                              _DAT_1000_46fe = (uint)DAT_1000_be1b;
                                              uVar6 = 0xc89;
                                            }
                                            else {
                                              DAT_1000_f33b = 0;
                                            }
                                          }
                                          uVar5 = uVar6;
                                          if ((((_DAT_1000_cac2 == 4) && (_DAT_1000_be5c == 0x13a))
                                              && (_DAT_1000_46fe == 0xfec6)) &&
                                             (DAT_1000_f33a == '\0')) {
                                            uVar5 = 0xc89;
                                            func_0x00016c68(uVar6,0x4ec);
                                            _DAT_1000_46fe = (uint)DAT_1000_be1b;
                                          }
                                          if ((0xb < (int)_DAT_1000_46fe) || (_DAT_1000_46fe == 5))
                                          {
                                            _DAT_1000_46fe = 10;
                                          }
                                          if (((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x130))
                                             && (DAT_1000_f33a == '\0')) {
                                            func_0x00016c68(uVar5,0x506);
                                            _DAT_1000_cae8 = 1;
                                          }
                                          else {
                                            uVar6 = uVar5;
                                            if ((((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x13a)
                                                 ) && (_DAT_1000_46fe == 0xfec6)) &&
                                               (DAT_1000_5f1e == '\x01')) {
                                              if (DAT_1000_f33a == '\0') {
                                                uVar6 = 0xc89;
                                                func_0x00016c68(uVar5,0x4f1);
                                              }
                                              else {
                                                func_0x00016c68(uVar5,0x4f7);
                                                uVar6 = 0xc89;
                                                func_0x00016c68(0xc89,0x4f8);
                                              }
                                            }
                                            uVar5 = uVar6;
                                            if (((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x130))
                                               && ((_DAT_1000_46fe == 0xfec6 &&
                                                   ((DAT_1000_f33a == '\x01' &&
                                                    (DAT_1000_f33c == '\0')))))) {
                                              DAT_1000_f33c = '\x01';
                                              uVar5 = 0xc89;
                                              func_0x00016c68(uVar6,0x50b);
                                            }
                                            if ((0x76 < DAT_1000_be1b) && (DAT_1000_be1b < 0x92)) {
                                              if ((_DAT_1000_cac2 == 2) && (_DAT_1000_be5c == 0x244)
                                                 ) {
                                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x829,uVar5
                                                               );
                                                func_0x0000f86c(0x2a97);
                                                _DAT_1000_4926 = 0x7e;
                                                DAT_1000_5384 = 3;
                                                _DAT_1000_755e = 0x1582;
                                                _DAT_1000_7560 = 0;
                                                _DAT_1000_cae8 = 1;
                                                DAT_1000_f359 = 0;
                                                return;
                                              }
                                              if (((DAT_1000_be1b < 0x79) || (0x7e < DAT_1000_be1b))
                                                 && (_DAT_1000_4928 == -1)) {
                                                func_0x00016c68(uVar5,0x1592);
                                                _DAT_1000_755e = 0x1582;
                                                _DAT_1000_7560 = 0;
                                                _DAT_1000_4926 = 0x7e;
                                                DAT_1000_5384 = 3;
                                                DAT_1000_f359 = 0;
                                                uVar5 = 0xc89;
                                              }
                                              if (DAT_1000_be1b == 0x77) {
                                                func_0x0002af9a(uVar5,0x876,uVar5,local_a,0x1000,
                                                                0x12e);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x87d,0xbc0,local_e,0x1000,
                                                                0x12f);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x889,0xbc0,local_8,0x1000,
                                                                0x130);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x88e,0xbc0,local_10,0x1000,
                                                                0x131);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89b,0xbc0,local_6,0x1000,
                                                                0x133);
                                                func_0x0000bc00(0x2a97);
                                              }
                                              else {
                                                func_0x0002af9a(uVar5,0x89f,uVar5,local_8,0x1000,
                                                                0x12e);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x12f);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x130);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x131);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x133);
                                                func_0x0000bc00(0x2a97);
                                              }
                                              if (DAT_1000_f368 == '\x01') {
                                                func_0x0002af9a(0xbc0,0x876,0xbc0,local_a,0x1000,
                                                                0x135);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x87d,0xbc0,local_e,0x1000,
                                                                0x136);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8a4,0xbc0,local_e,0x1000,
                                                                0x137);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8b0,0xbc0,local_c,0x1000,
                                                                0x138);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8ba,0xbc0,local_c,0x1000,
                                                                0x139);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8c4,0xbc0,local_a,0x1000,
                                                                0x13a);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89b,0xbc0,local_6,0x1000,
                                                                0x13b);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8cb,0xbc0,local_a,0x1000,
                                                                0x13c);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8d2,0xbc0,local_a,0x1000,
                                                                0x13d);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8da,0xbc0,local_8,0x1000,
                                                                0x13e);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x8df,0xbc0,local_a,0x1000,
                                                                0x13f);
                                                func_0x0000bc00(0x2a97);
                                              }
                                              else {
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x135);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x136);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x137);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x138);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x139);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x13a);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x13b);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x13c);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x13d);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x13e);
                                                func_0x0000bc00(0x2a97);
                                                func_0x0002af9a(0xbc0,0x89f,0xbc0,local_8,0x1000,
                                                                0x13f);
                                                func_0x0000bc00(0x2a97);
                                              }
                                              uVar5 = 0xbc0;
                                              if (DAT_1000_be1b != 0x87) {
                                                DAT_1000_f360 = 3;
                                              }
                                              if (DAT_1000_be1b != 0x88) {
                                                DAT_1000_f364 = 0;
                                              }
                                              if (DAT_1000_be1b != 0x89) {
                                                DAT_1000_f367 = 0;
                                              }
                                            }
                                            if (((0x8a < DAT_1000_be1b) && (DAT_1000_be1b < 0x8e))
                                               && (DAT_1000_f36d != '\0')) {
                                              if (DAT_1000_f36d == '\x01') {
                                                func_0x00016c68(uVar5,0x17e6);
                                                uVar6 = 0xc89;
                                              }
                                              else if (DAT_1000_f36d == '\x02') {
                                                func_0x00016c68(uVar5,0x17e9);
                                                uVar6 = 0xc89;
                                              }
                                              else if (DAT_1000_f36d == '\x03') {
                                                func_0x00016c68(uVar5,0x17eb);
                                                uVar6 = 0xc89;
                                              }
                                              else if (DAT_1000_f36d == '\x04') {
                                                func_0x00016c68(uVar5,0x17ef);
                                                uVar6 = 0xc89;
                                              }
                                              else if (DAT_1000_f36d == '\x05') {
                                                func_0x00016c68(uVar5,0x17f0);
                                                uVar6 = 0xc89;
                                              }
                                              else {
                                                uVar6 = uVar5;
                                                if (DAT_1000_f36d == '\x06') {
                                                  uVar6 = 0xc89;
                                                  func_0x00016c68(uVar5,0x17f1);
                                                  DAT_1000_be1b = 0x1a;
                                                  _DAT_1000_cac2 = 3;
                                                  _DAT_1000_be5c = 0;
                                                }
                                              }
                                              DAT_1000_f36d = DAT_1000_f36d + '\x01';
                                              uVar5 = uVar6;
                                            }
                                            if (((0x8a < DAT_1000_be1b) && (DAT_1000_be1b < 0x8d))
                                               && (DAT_1000_f370 != '\0')) {
                                              DAT_1000_f370 = DAT_1000_f370 + '\x01';
                                              uVar6 = uVar5;
                                              if (DAT_1000_f370 == '\x02') {
                                                uVar6 = 0xc89;
                                                func_0x00016c68(uVar5,0x180e);
                                              }
                                              uVar7 = uVar6;
                                              if (DAT_1000_f370 == '\x06') {
                                                uVar7 = 0xc89;
                                                func_0x00016c68(uVar6,0x1813);
                                              }
                                              uVar5 = uVar7;
                                              if (DAT_1000_f370 == '\v') {
                                                uVar5 = 0xc89;
                                                func_0x00016c68(uVar7,0x1818);
                                              }
                                              if (DAT_1000_f370 == '\f') {
                                                DAT_1000_f370 = '\x02';
                                              }
                                            }
                                            if ((0x8a < DAT_1000_be1b) && (DAT_1000_be1b < 0x8d)) {
                                              if ((_DAT_1000_cac2 == 2) && (_DAT_1000_be5c == 0x2b4)
                                                 ) {
                                                func_0x00016c68(uVar5,0x181c);
                                                _DAT_1000_4a06 = 0x8c;
                                                _DAT_1000_4a18 = (uint)DAT_1000_be1b;
                                                DAT_1000_53f4 = 3;
                                                _DAT_1000_cae8 = 1;
                                                DAT_1000_f371 = 1;
                                                return;
                                              }
                                              if (((_DAT_1000_cac2 == 1) &&
                                                  (_DAT_1000_be5c == 0x2bd)) &&
                                                 (DAT_1000_f371 == '\x01')) {
                                                if (DAT_1000_f372 == '\x01') {
                                                  func_0x00016c68(uVar5,0x1826);
                                                  _DAT_1000_cae8 = 1;
                                                  return;
                                                }
                                                func_0x00016c68(uVar5,0x1820);
                                                _DAT_1000_4a18 = 0xffff;
                                                DAT_1000_53fd = 1;
                                                _DAT_1000_cae8 = 1;
                                                DAT_1000_f371 = 0;
                                                DAT_1000_f372 = 1;
                                                return;
                                              }
                                              if (DAT_1000_f371 == '\x01') {
                                                DAT_1000_f371 = '\0';
                                                _DAT_1000_4a18 = 0;
                                                func_0x00016c68(uVar5,0x1824);
                                                uVar5 = 0xc89;
                                              }
                                            }
                                            if ((0x76 < DAT_1000_be1b) && (DAT_1000_be1b < 0x9b)) {
                                              if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x2bd)
                                                 ) {
                                                func_0x00016c68(uVar5,_DAT_1000_7652);
                                                _DAT_1000_cae8 = 1;
                                                if (_DAT_1000_44cc == -0x2bd) {
                                                  func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x8e6,
                                                                  0xc89);
                                                  uVar5 = 0xc89;
                                                  func_0x0000f86c(0x2a97);
                                                }
                                                else {
                                                  func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x901,
                                                                  0xc89);
                                                  uVar5 = 0xc89;
                                                  func_0x0000f86c(0x2a97);
                                                }
                                              }
                                              if ((_DAT_1000_4a18 == 0x8d) &&
                                                 (DAT_1000_f36c == '\x02')) {
                                                _DAT_1000_44cc = -0x2bd;
                                                DAT_1000_5157 = 3;
                                                if (DAT_1000_be1b == 0x8d) {
                                                  func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x915,
                                                                  uVar5);
                                                  uVar5 = 0xc89;
                                                  func_0x0000f86c(0x2a97);
                                                }
                                              }
                                              if (((0x8a < DAT_1000_be1b) && (DAT_1000_be1b < 0x8e))
                                                 && (DAT_1000_f373 != 0)) {
                                                DAT_1000_f373 = DAT_1000_f373 + 1;
                                                uVar6 = uVar5;
                                                if (DAT_1000_be1b != DAT_1000_f374) {
                                                  uVar6 = 0xc89;
                                                  func_0x00016c68(uVar5,0x182f);
                                                }
                                                if (DAT_1000_be1b == 0x8d) {
                                                  func_0x00016c68(uVar6,0x1841);
                                                  DAT_1000_be1b = 0x1a;
                                                  _DAT_1000_be5c = 0;
                                                  _DAT_1000_cac2 = 3;
                                                  return;
                                                }
                                                uVar5 = uVar6;
                                                if (2 < DAT_1000_f373) {
                                                  uVar5 = 0xc89;
                                                  func_0x00016c68(uVar6,0x1832);
                                                  _DAT_1000_cae8 = 1;
                                                  DAT_1000_37f9 = 1;
                                                  DAT_1000_f36c = '\x03';
                                                  DAT_1000_f373 = 0;
                                                }
                                              }
                                              DAT_1000_f374 = DAT_1000_be1b;
                                              if ((((_DAT_1000_cac2 == 2) ||
                                                   (_DAT_1000_cac2 == 0x3e)) &&
                                                  ((_DAT_1000_be5e == 0x2bd ||
                                                   (_DAT_1000_be5e == 0x17)))) &&
                                                 (_DAT_1000_be5c == 0x2a6)) {
                                                _DAT_1000_be5c = 0x2bd;
                                                _DAT_1000_be5e = 0x2a6;
                                              }
                                              if ((((0x8a < DAT_1000_be1b) && (DAT_1000_be1b < 0x8d)
                                                   ) && ((DAT_1000_be1b == _DAT_1000_49ea &&
                                                         ((_DAT_1000_cac2 == 2 ||
                                                          (_DAT_1000_cac2 == 0x3e)))))) &&
                                                 (((_DAT_1000_be5c == 0x2bd ||
                                                   (_DAT_1000_be5c == 0x17)) &&
                                                  (_DAT_1000_be5e == 0x2a6)))) {
                                                if (_DAT_1000_44cc == -0x2bd) {
                                                  _DAT_1000_6982 = 0x1808;
                                                  _DAT_1000_7624 = 0x1808;
                                                  _DAT_1000_44cc = 0;
                                                  DAT_1000_5157 = 3;
                                                  _DAT_1000_cae8 = 1;
                                                  func_0x00016c68(uVar5,0x1803);
                                                  func_0x00016c68(0xc89,0x1808);
                                                  DAT_1000_f36a = 1;
                                                  return;
                                                }
                                                func_0x0002afb4(uVar5,0xff,0xcaea,0x1000,0x936,uVar5
                                                               );
                                                func_0x0000f86c(0x2a97);
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                            }
                                            if ((0x91 < DAT_1000_be1b) && (DAT_1000_be1b < 0x9e)) {
                                              if ((((_DAT_1000_cac2 == 3) &&
                                                   (_DAT_1000_be5c == 0x333)) ||
                                                  (_DAT_1000_cac2 == 0x26)) &&
                                                 (((DAT_1000_be1b == _DAT_1000_4b24 ||
                                                   (_DAT_1000_4b24 == 0xffff)) ||
                                                  (DAT_1000_be1b == 0x92)))) {
                                                func_0x00016c68(uVar5,0x2747);
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                              if ((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x32f)
                                                 ) {
                                                func_0x00016c68(uVar5,0x2755);
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                              if (((_DAT_1000_4b6c == 0x96) &&
                                                  (DAT_1000_f382 == -0x68)) &&
                                                 (DAT_1000_f389 == '\0')) {
                                                func_0x0001bffd(uVar5,0x2a);
                                                DAT_1000_f2d6 = 1;
                                                func_0x00016c68(0x1bab,0x27e4);
                                                _DAT_1000_4b0a = 0;
                                                _DAT_1000_6aa2 = 0;
                                                DAT_1000_cda0 = 0x28;
                                                DAT_1000_f382 = 0;
                                                DAT_1000_f389 = 1;
                                                return;
                                              }
                                              uVar6 = uVar5;
                                              if (DAT_1000_f389 == '\x01') {
                                                DAT_1000_f389 = '\x02';
                                                uVar6 = 0xc89;
                                                func_0x00016c68(uVar5,0x27ec);
                                              }
                                              if (DAT_1000_f382 == -0x68) {
                                                _DAT_1000_6aa2 = 0x28b4;
                                              }
                                              else {
                                                _DAT_1000_6aa2 = 0;
                                              }
                                              if ((0x92 < _DAT_1000_4b36) && (_DAT_1000_4b36 < 0x98)
                                                 ) {
                                                func_0x00016c68(uVar6,0x279b);
                                                DAT_1000_f385 = DAT_1000_4b36;
                                                if (_DAT_1000_4b36 == 0x97) {
                                                  func_0x00016c68(0xc89,0x279e);
                                                  DAT_1000_f386 = '\0';
                                                  DAT_1000_f385 = 0;
                                                  _DAT_1000_4b3e = 0;
                                                  _DAT_1000_4b3a = 0;
                                                }
                                                uVar6 = 0xc89;
                                                _DAT_1000_4b36 = 0x9d;
                                                DAT_1000_548c = 3;
                                              }
                                              if (DAT_1000_f385 == DAT_1000_be1b) {
                                                if (DAT_1000_f387 == '\x02') {
                                                  func_0x0001bffd(uVar6,0x2c);
                                                  func_0x00016c68(0x1bab,0x27af);
                                                  _DAT_1000_cac2 = 3;
                                                  _DAT_1000_be5c = 0;
                                                  DAT_1000_be1b = 0x1a;
                                                  _DAT_1000_f2ae = 1;
                                                  uVar6 = 0xc89;
                                                  func_0x0000fdcf(0xc89);
                                                }
                                                uVar7 = uVar6;
                                                if (DAT_1000_f387 == '\x01') {
                                                  uVar7 = 0xc89;
                                                  func_0x00016c68(uVar6,0x27ad);
                                                  DAT_1000_f387 = '\x02';
                                                }
                                                uVar5 = uVar7;
                                                if (DAT_1000_f387 == '\0') {
                                                  uVar5 = 0xc89;
                                                  func_0x00016c68(uVar7,0x27aa);
                                                  DAT_1000_f387 = '\x01';
                                                }
                                              }
                                              else {
                                                DAT_1000_f387 = '\0';
                                                uVar5 = uVar6;
                                              }
                                              if (DAT_1000_f385 == 0x94) {
                                                _DAT_1000_6ad2 = 0x278a;
                                              }
                                              else {
                                                _DAT_1000_6ad2 = 0;
                                              }
                                              if (DAT_1000_f385 == DAT_1000_be1b) {
                                                _DAT_1000_6ad2 = 0;
                                              }
                                              if (DAT_1000_f385 == 0x97) {
                                                _DAT_1000_6ad2 = 0;
                                              }
                                              if (DAT_1000_f386 == -0x69) {
                                                _DAT_1000_6ad6 = 0x278e;
                                                if (DAT_1000_be1b == 0x95) {
                                                  _DAT_1000_6ad6 = 0x27b8;
                                                }
                                              }
                                              else {
                                                _DAT_1000_6ad6 = 0;
                                              }
                                              if ((DAT_1000_f386 == -0x69) &&
                                                 (DAT_1000_be1b == 0x97)) {
                                                _DAT_1000_6ad6 = 0x27f9;
                                              }
                                            }
                                            if ((0x45 < DAT_1000_be1b) && (DAT_1000_be1b < 100)) {
                                              if ((DAT_1000_be1b == 0x46) ||
                                                 ((((DAT_1000_be1b == 0x48 ||
                                                    (DAT_1000_be1b == 0x4a)) ||
                                                   (DAT_1000_be1b == 0x4e)) ||
                                                  (DAT_1000_be1b == 0x50)))) {
                                                _DAT_1000_48fe = (uint)DAT_1000_be1b;
                                              }
                                              if ((((DAT_1000_be1b == 0x46) ||
                                                   (DAT_1000_be1b == 0x48)) ||
                                                  (DAT_1000_be1b == 0x4b)) &&
                                                 ((_DAT_1000_4902 = (uint)DAT_1000_be1b,
                                                  _DAT_1000_cac2 == 0x66 &&
                                                  ((_DAT_1000_be5c == 0x232 ||
                                                   (_DAT_1000_be5e == 0x232)))))) {
                                                func_0x00016c68(uVar5,0x6357);
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                              if ((_DAT_1000_cac2 == 3) && (_DAT_1000_be5c == 0x271)
                                                 ) {
                                                func_0x00016c68(uVar5,_DAT_1000_75ba);
                                                if (_DAT_1000_4982 == -0x271) {
                                                  func_0x00016c68(0xc89,0x6461);
                                                }
                                                else {
                                                  func_0x00016c68(0xc89,0x6464);
                                                }
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                              uVar6 = uVar5;
                                              if ((_DAT_1000_cac2 == 1) && (_DAT_1000_be5c == 0x272)
                                                 ) {
                                                uVar6 = 0xc89;
                                                func_0x00016c68(uVar5,0x6465);
                                              }
                                              if ((_DAT_1000_cac2 == 0x3e) &&
                                                 (_DAT_1000_be5c == 0x271)) {
                                                _DAT_1000_be5c = 0x272;
                                              }
                                              if ((_DAT_1000_cac2 == 0x3e) &&
                                                 (_DAT_1000_be5e == 0x271)) {
                                                _DAT_1000_be5e = 0x272;
                                              }
                                              if (((_DAT_1000_cac2 == 0x3e) &&
                                                  (_DAT_1000_be5e == 0x272)) &&
                                                 (_DAT_1000_be5c == 0x2ae)) {
                                                _DAT_1000_be5c = 0x272;
                                                _DAT_1000_be5e = 0x2ae;
                                              }
                                              if (((_DAT_1000_cac2 == 0x3e) &&
                                                  (_DAT_1000_be5c == 0x272)) &&
                                                 (_DAT_1000_be5e == 0x2ae)) {
                                                func_0x00016c68(uVar6,0x6468);
                                                _DAT_1000_4982 = 0xfd52;
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                              if (_DAT_1000_be5c == 0x274) {
                                                _DAT_1000_be5c = 0x273;
                                              }
                                              if (_DAT_1000_be5e == 0x274) {
                                                _DAT_1000_be5e = 0x274;
                                              }
                                              if ((_DAT_1000_cac2 == 0x39) &&
                                                 (_DAT_1000_be5c == 0x273)) {
                                                _DAT_1000_cac2 = 3;
                                              }
                                              if ((_DAT_1000_cac2 == 0x25) &&
                                                 (_DAT_1000_be5c == 0x2b9)) {
                                                func_0x00016c68(uVar6,0x652a);
                                                DAT_1000_f3ed = 1;
                                                if (DAT_1000_f3ee == '\x01') {
                                                  func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x962,
                                                                  0xc89);
                                                  func_0x0000f86c(0x2a97);
                                                }
                                                _DAT_1000_4a10 = 0;
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                              if ((DAT_1000_f3ed == '\x01') &&
                                                 (DAT_1000_f3ee == '\0')) {
                                                if ((_DAT_1000_cac2 == 0x25) &&
                                                   (_DAT_1000_be5c == 0x2ca)) {
                                                  DAT_1000_f3ee = 1;
                                                  func_0x00016c68(uVar6,0x65b9);
                                                  func_0x0002afb4(0xc89,0xff,0xcaea,0x1000,0x9a4,
                                                                  0xc89);
                                                  func_0x0000f86c(0x2a97);
                                                  _DAT_1000_4a32 = 0;
                                                  _DAT_1000_cae8 = 1;
                                                  return;
                                                }
                                                DAT_1000_be1b = 0x1a;
                                                _DAT_1000_cac2 = 3;
                                                func_0x00016c68(uVar6,0x652c);
                                                func_0x00015206(0xc89);
                                                func_0x00016c68(0xc89,0x6534);
                                                func_0x00015206(0xc89);
                                                func_0x00016c68(0xc89,0x6538);
                                                _DAT_1000_be5c = 0;
                                                return;
                                              }
                                              uVar5 = uVar6;
                                              if ((_DAT_1000_cac2 == 0x25) &&
                                                 (_DAT_1000_be5c == 0x2ca)) {
                                                DAT_1000_f3ee = 1;
                                                func_0x00016c68(uVar6,0x65b9);
                                                _DAT_1000_4a32 = 0;
                                                _DAT_1000_cae8 = 1;
                                                return;
                                              }
                                            }
                                            if (0x9f < DAT_1000_be1b) {
                                              func_0x00006dbe(uVar5);
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  return;
}

