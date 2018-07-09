use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

# Text::Iconv is not really required.
# This can be any object with the convert method. Or nothing.

use Spreadsheet::XLSX;

open $if, "< ./test.xlsx"  or die "Can't open file to read\n";

my $excel = Spreadsheet::XLSX -> new ('test.xlsx', $converter);

##Global 
my $addr; ##address (dec)
my $name; ##name
my $bits; ##bits
my $attr; ##Attribute
my $dfvl; ##default value
my $cur_addr;
my $cur_start_bit;
my $cur_end_bit;
my $cur_name_start_bit;
my $cur_name_end_bit;
my $cur_offset;
my $cur_row;
my $cur_reg_no;
my $cur_dfvl_reg_no;
my $cur_ro_reg_no;
my $cur_name;
my @bits_arr;
my @name_arr;

##For Write and Read
my $addr_no;           ##total address numbers per sheet
my @addr_array;        ##Store all address
my @addr_reg_bit_vld;  ##2-D array, valid bits of each address

##For Write
my @addr_reg_no;       ##1-D array, valid register numbers of each address, max 32
my @addr_reg_addr;     ##1-D array, valid register address of each address, max 32
my @addr_reg_name;     ##2-D array, valid register names of each address, max 32 names array
my @addr_reg_bits;     ##2-D array, valid register bits of each address, max 32 names array
my @addr_reg_mask;     ##2-D array, valid mask sets of each addresss, max 32 mask array

##For Read
my @addr_ro_reg_no;    ##1-D array, valid register numbers of each address, max 32
my @addr_ro_reg_addr;  ##1-D array, valid register address of each address, max 32
my @addr_ro_reg_name;  ##2-D array, valid register names of each address, max 32 names array
my @addr_ro_reg_bits;     ##2-D array, valid register bits of each address, max 32 names array

##For Write default value array
my @addr_dv_reg_no;    ##1-D array, valid register numbers of each address, max 32
my @addr_dv_reg_name;  ##2-D array, valid register names of each address, max 32 names array
my @addr_dv_reg_dfvl;  ##2-D array, valid register default value of each addresss, max 32 mask array

$addr_no = 0;

#########################################
## Scan each Sheet
#########################################
foreach my $sheet (@{$excel -> {Worksheet}}) {

   open $of, "> ./$sheet->{Name}.v" or die "Can't open file to write\n";

   $sheet -> {MaxRow} ||= $sheet -> {MinRow};

   foreach my $row ($sheet -> {MinRow} .. $sheet -> {MaxRow}) {
     $sheet -> {MaxCol} ||= $sheet -> {MinCol};
   }
    
   printf     "//Created by xls_gen_reg.pl \n";
   $datestring = localtime();
   printf     "//$datestring\n\n";

   my $min_row = $sheet -> {MinRow};
   #printf "min_row:".$min_row."\n";
   my $max_row = $sheet -> {MaxRow};
   #printf "max_row:".$max_row."\n";
   my $min_col = $sheet -> {MinCol};
   #printf "min_col:".$min_col."\n";
   my $max_col = $sheet -> {MaxCol};
   #printf "max_col:".$max_col."\n\n\n";
   
   #########################################
   ## Scan each Row
   #########################################
   foreach $i ($min_row+1 .. $max_row) {
       $addr  = ($sheet -> {Cells} [$i] [$min_col+1]) -> {Val}; ##address (dec)
       $name  = ($sheet -> {Cells} [$i] [$min_col+3]) -> {Val}; ##name
       $bits  = ($sheet -> {Cells} [$i] [$min_col+4]) -> {Val}; ##bits
       $dfvl  = ($sheet -> {Cells} [$i] [$min_col+5]) -> {Val}; ##Default value
       $attr  = ($sheet -> {Cells} [$i] [$min_col+6]) -> {Val}; ##Attribute
       $cur_row = $i;

       #printf "addr= ".$addr."\n"; 
       #printf "name= ".$name."\n"; 
       #printf "bits= ".$bits."\n"; 
       #printf "dfvl= ".$dfvl."\n"; 
       #printf "attr= ".$attr."\n"; 

       if($addr != 0) {
         $cur_addr = $addr;
         #printf "cur_addr= ".$cur_addr."\n"; 
       }

       ## Split bus
       @bits_arr = split(/:/,  $bits);
       @name_arr = split('\[', $name);

       if($addr ne ""){
         $addr_no = $addr_no + 1;
         #reset all address array of this new address
         addr_array_init();
         check_address_duplicate();
       }

       # Check missing address of first register 
       check_first_address_err();

       # Check missing name/bits/attribute/default value
       check_missing();

       # Add register to dfvl array
       addr_reg_to_dfvl_array();

       # Add register to write and read array
       if(@bits_arr > 1) { ##bits is bus
           # Parse name and bits 
           parse_bus_name_bit();
           # Check name/bits/ mismatch
           check_bus_name_bit_mismatch(); 
           # Check bits duplicate defined
           check_bus_bit_duplicate(); 
           ##Check pass, add this register to array
           if($attr eq "RW"){
              add_bus_reg_to_array(); 
              add_reg_to_ro_array(); 
           } else {
              add_reg_to_ro_array(); 
           }
       } else { ## bits Not a bus
           # Check name/bits/ mismatch
           check_name_bit_mismatch(); 
           # Check bits duplicate defined
           check_bit_duplicate(); 
           ##Check pass, add this register to array
           if($attr eq "RW"){
              add_reg_to_array();
              add_reg_to_ro_array();
           } else {
              add_reg_to_ro_array();
           }
       }
       #printf "\n\n";
   } ## for each row

   # All done, start printing verilog file
   print_verilog(); 
   $file_name = "./$sheet->{Name}.v";
   printf     "File: ".$file_name." is ready.. Please check it. \n";
} ##for each sheet

##--------------------------------------------------------------------------------------------------
sub addr_reg_to_dfvl_array {
    $addr_dv_reg_no[$addr_no]++;$cur_dfvl_reg_no=$addr_dv_reg_no[$addr_no];
    $addr_dv_reg_name[$addr_no][$cur_dfvl_reg_no] = $name; 
    $addr_dv_reg_dfvl[$addr_no][$cur_dfvl_reg_no] = $dfvl;
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub print_verilog {
   ##for($i=1; $i<=$addr_no; $i++) {
   ##    printf "  addr cnt= ".$i."\n";
   ##  for($j=1; $j<=$addr_reg_no[$i]; $j++) {
   ##    printf "- addr_reg_addr[".$i."]   : ".$addr_reg_addr[$i]."\n";
   ##    printf "- addr_reg_name[".$i."][$j]: ".$addr_reg_name[$i][$j]."\n";
   ##    printf "- addr_reg_bits[".$i."][$j]: ".$addr_reg_bits[$i][$j]."\n";
   ##    printf "- addr_reg_mask[".$i."][$j]: ".$addr_reg_mask[$i][$j]."\n";
   ##    printf "- addr_reg_dfvl[".$i."][$j]: ".$addr_reg_dfvl[$i][$j]."\n";
   ##  }
   ##  for($k=1; $k<=$addr_ro_reg_no[$i]; $k++) {
   ##    printf "- addr_ro_reg_addr[".$i."]   : ".$addr_ro_reg_addr[$i]."\n";
   ##    printf "- addr_ro_reg_name[".$i."][$k]: ".$addr_ro_reg_name[$i][$k]."\n";
   ##    printf "- addr_ro_reg_bits[".$i."][$k]: ".$addr_ro_reg_bits[$i][$k]."\n";
   ##  }
   ##    printf "\n";
   ##}
   print_reg_write();
   print_reg_read();
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub print_reg_read{
   printf $of  "//========================\n";
   printf $of  "//Register Read logic\n";
   printf $of  "//========================\n";
   printf $of  "always @(*) begin\n";
   printf $of  "  phy_regout = 32'h0;\n\n";

   for($i=1; $i<=$addr_no; $i++) {
     printf $of  "  if(int_reg_read_command && (int_reg_phy_addr == ".$addr_ro_reg_addr[$i].") begin\n";

     for($j=1; $j<=$addr_ro_reg_no[$i]; $j++) {
       #printf $of  "    phy_regout".$addr_ro_reg_bits[$i][$j]." = ".$addr_ro_reg_name[$i][$j].";\n";
       printf $of  "    phy_regout%-10s = %-20s\n", $addr_ro_reg_bits[$i][$j], $addr_ro_reg_name[$i][$j].";";
     }
     printf $of  "  end\n";
   }      
   printf $of  "end\n";
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub print_reg_write{
   my $first_print;
   my $mask_exist;
   printf $of  "//========================\n";
   printf $of  "//Register Write logic\n";
   printf $of  "//========================\n";
   for($i=1; $i<=$addr_no; $i++) {
      printf $of  "//Register[".$addr_reg_addr[$i]."]\n";
      printf $of  "always @(posedge clk2 or negedge rst_n)\n";
      printf $of  "  if(!rst_n) begin\n";

      for($j=1; $j<=$addr_dv_reg_no[$i]; $j++) {
          #printf $of  "        ".$addr_dv_reg_name[$i][$j]." <= ".$addr_dv_reg_dfvl[$i][$j].";\n";
          printf $of  "        %-30s <= %-30s\n",$addr_dv_reg_name[$i][$j],$addr_dv_reg_dfvl[$i][$j].";";
      } 

      printf $of  "  end\n";
      printf $of  "  else if(int_reg_write && int_reg_command_valid) begin\n";
      printf $of  "    if(int_reg_phy_addr == ".$addr_reg_addr[$i].") begin\n";
      ##mask[3]
      $first_print = 0;
      $mask_exist  = 0;
      for($j=1; $j<=$addr_reg_no[$i]; $j++) {
         if($addr_reg_mask[$i][$j] == 3) {
           $mask_exist  = 1;
           if($first_print == 0) {
              printf $of  "      if(int_reg_mask[3] == 1'b0) begin\n";
              $first_print = 1;
           }
           #printf $of  "        ".$addr_reg_name[$i][$j]." <= int_regin".$addr_reg_bits[$i][$j].";\n";
           printf $of  "        %-30s <= int_regin%-10s\n",$addr_reg_name[$i][$j],$addr_reg_bits[$i][$j].";";
         }
      }
      if($mask_exist == 1) {
        printf $of  "      end\n";
        $mask_exist  = 0;
      }

      ##mask[2]
      $first_print = 0;
      $mask_exist  = 0;
      for($j=1; $j<=$addr_reg_no[$i]; $j++) {
         if($addr_reg_mask[$i][$j] == 2) {
           $mask_exist  = 1;
           if($first_print == 0) {
              printf $of  "      if(int_reg_mask[2] == 1'b0) begin\n";
              $first_print = 1;
           }
           #printf $of  "        ".$addr_reg_name[$i][$j]." <= int_regin".$addr_reg_bits[$i][$j].";\n";
           printf $of  "        %-30s <= int_regin%-10s\n",$addr_reg_name[$i][$j],$addr_reg_bits[$i][$j].";";
         }
      }
      if($mask_exist == 1) {
        printf $of  "      end\n";
        $mask_exist  = 0;
      }

      ##mask[1]
      $first_print = 0;
      $mask_exist  = 0;
      for($j=1; $j<=$addr_reg_no[$i]; $j++) {
         if($addr_reg_mask[$i][$j] == 1) {
           $mask_exist  = 1;
           if($first_print == 0) {
              printf $of  "      if(int_reg_mask[1] == 1'b0) begin\n";
              $first_print = 1;
           }
           #printf $of  "        ".$addr_reg_name[$i][$j]." <= int_regin".$addr_reg_bits[$i][$j].";\n";
           printf $of  "        %-30s <= int_regin%-10s\n",$addr_reg_name[$i][$j],$addr_reg_bits[$i][$j].";";
         }
      }
      if($mask_exist == 1) {
        printf $of  "      end\n";
        $mask_exist  = 0;
      }

      ##mask[0]
      $first_print = 0;
      $mask_exist  = 0;
      for($j=1; $j<=$addr_reg_no[$i]; $j++) {
         if($addr_reg_mask[$i][$j] == 0) {
           $mask_exist  = 1;
           if($first_print == 0) {
              printf $of  "      if(int_reg_mask[0] == 1'b0) begin\n";
              $first_print = 1;
           }
           #printf $of  "        ".$addr_reg_name[$i][$j]." <= int_regin".$addr_reg_bits[$i][$j].";\n";
           printf $of  "        %-30s <= int_regin%-10s\n",$addr_reg_name[$i][$j],$addr_reg_bits[$i][$j].";";
         }
      }
      if($mask_exist == 1) {
        printf $of  "      end\n";
        $mask_exist  = 0;
      }

      printf $of  "    end \n";
      printf $of  "  end \n\n\n";
  }
}
##--------------------------------------------------------------------------------------------------

sub check_address_duplicate {
  for($i=1; $i<$addr_no; $i++) {
     if($addr eq $addr_array[$i]) {
       printf "ERROR!! Row ".$cur_row.": Address has been defined before, Go check it... address: ".$addr."\n";
       exit;
     }
  }

  $addr_array[$addr_no] = $addr;
}

##--------------------------------------------------------------------------------------------------
sub add_reg_to_ro_array {
    $addr_ro_reg_no[$addr_no]++;$cur_ro_reg_no=$addr_ro_reg_no[$addr_no];
    $addr_ro_reg_addr[$addr_no]=$cur_addr;
    $addr_ro_reg_name[$addr_no][$cur_ro_reg_no]=$name;
    $addr_ro_reg_bits[$addr_no][$cur_ro_reg_no]="[".$bits."]";
}

##--------------------------------------------------------------------------------------------------
sub add_reg_to_array {
   if($bits >= 24) {
      $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
      $addr_reg_addr[$addr_no]=$cur_addr;
      $addr_reg_name[$addr_no][$cur_reg_no]=$name;
      $addr_reg_bits[$addr_no][$cur_reg_no]="[".$bits."]";
      $addr_reg_mask[$addr_no][$cur_reg_no]=3;
   } elsif($bits >=16) {
      $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
      $addr_reg_addr[$addr_no]=$cur_addr;
      $addr_reg_name[$addr_no][$cur_reg_no]=$name;
      $addr_reg_bits[$addr_no][$cur_reg_no]="[".$bits."]";
      $addr_reg_mask[$addr_no][$cur_reg_no]=2;
   } elsif($bits >=8) {
      $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
      $addr_reg_addr[$addr_no]=$cur_addr;
      $addr_reg_name[$addr_no][$cur_reg_no]=$name;
      $addr_reg_bits[$addr_no][$cur_reg_no]="[".$bits."]";
      $addr_reg_mask[$addr_no][$cur_reg_no]=1;
   } else {
      $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
      $addr_reg_addr[$addr_no]=$cur_addr;
      $addr_reg_name[$addr_no][$cur_reg_no]=$name;
      $addr_reg_bits[$addr_no][$cur_reg_no]="[".$bits."]";
      $addr_reg_mask[$addr_no][$cur_reg_no]=0;
   }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub add_bus_reg_to_array {
   if($cur_start_bit >= 24) {
      add_cond_cur_start_bit_gt_24();
   } elsif($cur_start_bit >=16) {
      add_cond_cur_start_bit_gt_16();
   } elsif($cur_start_bit >=8) {
      add_cond_cur_start_bit_gt_8();
   } else {
      add_cond_cur_start_bit_gt_0();
   }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub add_cond_cur_start_bit_gt_24 {       
           if($cur_end_bit >= 24) {
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".$cur_name_end_bit."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":".$cur_end_bit."]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=3;
           } elsif($cur_end_bit >= 16) {
                 if($cur_start_bit == 24) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[24]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=3;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".(24-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":24]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=3;
                 }
                 if($cur_end_bit == 23) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(23-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[23]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(23-$cur_offset).":".($cur_end_bit-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[23:".$cur_end_bit."]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 }
           } elsif($cur_end_bit >= 8) {
                 if($cur_start_bit == 24) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[24]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=3;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".(24-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":24]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=3;
                 }
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(23-$cur_offset).":".(16-$cur_offset)."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[23:16]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 if($cur_end_bit == 15) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(15-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[15]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(15-$cur_offset).":".($cur_end_bit-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[15:".$cur_end_bit."]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 }
           } else {
                 if($cur_start_bit == 24) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[24]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=3;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".(24-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":24]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=3;
                 }
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(23-$cur_offset).":".(16-$cur_offset)."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[23:16]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(15-$cur_offset).":".(8-$cur_offset)."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[15:8]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 if($cur_end_bit == 7) {
                    $addr_reg_no[$addr_no]++; $cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(7-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[7]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=0;
                 } else {
                    $addr_reg_no[$addr_no]++; $cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(7-$cur_offset).":".($cur_end_bit-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[7:".$cur_end_bit."]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=0;
                 }
           }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub add_cond_cur_start_bit_gt_16 {       
           if($cur_end_bit >= 16) {
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".($cur_end_bit-$cur_offset)."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":".$cur_end_bit."]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=2;
           } elsif($cur_end_bit >= 8) {
                 if($cur_start_bit == 16) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[16]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".(16-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":16]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 }
                 if($cur_end_bit == 15) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(15-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[15]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(15-$cur_offset).":".($cur_end_bit-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[15:".$cur_end_bit."]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 }
           } else {
                 if($cur_start_bit == 16) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[16]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".(16-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":16]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=2;
                 }
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(15-$cur_offset).":".(8-$cur_offset)."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[15:8]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 if($cur_end_bit == 7) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(7-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[7]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=0;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(7-$cur_offset).":".($cur_end_bit-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[7:".$cur_end_bit."]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=0;
                 }
           } 
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub add_cond_cur_start_bit_gt_8 {       
           if($cur_end_bit >= 8) {
                 $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                 $addr_reg_addr[$addr_no]=$cur_addr;
                 $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".($cur_end_bit-$cur_offset)."]";
                 $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":".$cur_end_bit."]";
                 $addr_reg_mask[$addr_no][$cur_reg_no]=1;
           } else {
                 if($cur_start_bit == 8) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[8]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".(8-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":8]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=1;
                    }
                 if($cur_end_bit == 7) {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(7-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[7]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=0;
                 } else {
                    $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
                    $addr_reg_addr[$addr_no]=$cur_addr;
                    $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".(7-$cur_offset).":".($cur_end_bit-$cur_offset)."]";
                    $addr_reg_bits[$addr_no][$cur_reg_no]="[7:".$cur_end_bit."]";
                    $addr_reg_mask[$addr_no][$cur_reg_no]=0;
                 }
           } 
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub add_cond_cur_start_bit_gt_0 {       
      $addr_reg_no[$addr_no]++;$cur_reg_no=$addr_reg_no[$addr_no];
      $addr_reg_addr[$addr_no]=$cur_addr;
      $addr_reg_name[$addr_no][$cur_reg_no]=$cur_name."[".$cur_name_start_bit.":".($cur_end_bit-$cur_offset)."]";
      $addr_reg_bits[$addr_no][$cur_reg_no]="[".$cur_start_bit.":".$cur_end_bit."]";
      $addr_reg_mask[$addr_no][$cur_reg_no]=0;
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub check_bus_bit_duplicate{
  for($i=$cur_start_bit; $i>=$cur_end_bit; $i--){
     if($addr_reg_bit_vld[$addr_no][$i] == 1) {
         printf "ERROR!! Row ".$cur_row.": bit[".$i."] of this signal name ".$name." has been defined before...\n";
         exit;
     }
     else {
       $addr_reg_bit_vld[$addr_no][$i] = 1;
     }
  }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub check_bit_duplicate{
     if($addr_reg_bit_vld[$addr_no][$bits] == 1) {
         printf "ERROR!! Row ".$cur_row.": bit[".$bits."] of this signal name ".$name." has been defined before...\n";
         exit;
     }
     else {
       $addr_reg_bit_vld[$addr_no][$bits] = 1;
     }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub addr_array_init {
   $addr_reg_no[$addr_no]  = 0;
   $addr_reg_addr[$addr_no]= $addr;
   for($i=1; $i<33; $i++){
     $addr_reg_name[$addr_no][$i]    = "";
     $addr_reg_bits[$addr_no][$i]    = "";
     $addr_reg_mask[$addr_no][$i]    = 0;
   }
   for($i=0; $i<32; $i++){
     $addr_reg_bit_vld[$addr_no][$i] = 0;
   } 

   $addr_ro_reg_no[$addr_no]  = 0;
   $addr_ro_reg_addr[$addr_no]= $addr;
   for($i=1; $i<33; $i++){
     $addr_ro_reg_name[$addr_no][$i]    = "";
     $addr_ro_reg_bits[$addr_no][$i]    = "";
   }

   $addr_dv_reg_no[$addr_no]  = 0;
   for($i=1; $i<33; $i++){
     $addr_dv_reg_name[$addr_no][$i]    = "";
     $addr_dv_reg_dfvl[$addr_no][$i]    = "";
   }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub parse_bus_name_bit{
   $cur_start_bit = $bits_arr[0];
   $cur_end_bit   = $bits_arr[1];
  
   if(@name_arr > 1) { ##name is bus
      my @name_arr_split_1   = split(/:/, $name_arr[1]); 
         $cur_name_start_bit = $name_arr_split_1[0];
      my @name_arr_split_2   = split(/]/, $name_arr_split_1[1]); 
         $cur_name_end_bit   = $name_arr_split_2[0];
   } else {
     printf "ERROR!! Row ".$cur_row.": Shoule be a bus, Signal name= ".$name."\n";
     exit;
   } 

   $cur_offset = $cur_start_bit - $cur_name_start_bit;
   $cur_name   = $name_arr[0];
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub check_name_bit_mismatch{
   if(@name_arr > 1) { ##name is bus
     printf "ERROR!! Row ".$cur_row.": Shoule be a 1-bit signal but name column is not, Signal name= ".$name."\n";
     exit;
   }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub check_bus_name_bit_mismatch{
         ##if comparison
         if(($cur_start_bit - $cur_end_bit) != ($cur_name_start_bit - $cur_name_end_bit)) {
           printf "ERROR!! Row ".$cur_row.": bit width is not equal to name bus width, Signal name= ".$name."\n";
           exit;
         } else {
           #printf "cur_addr: ".$cur_addr."\n"; 
           #printf "cur_name_start_bit: ".$cur_name_start_bit."\n"; 
           #printf "cur_name_end_bit:   ".$cur_name_end_bit."\n"; 
           #printf "cur_start_bit: ".$cur_start_bit."\n"; 
           #printf "cur_start_bit: ".$cur_end_bit."\n"; 
         } ##if comparison
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub check_missing {
              if($name eq "") { 
                 printf "ERROR!! Row ".$cur_row.": Missing signal name\n";
                 exit;
              }
              if($bits eq "") { 
                 printf "ERROR!! Row ".$cur_row.": Missing signal bits\n";
                 exit;
              }
              if($attr eq "") { 
                 printf "ERROR!! Row ".$cur_row.": Missing signal attribute\n";
                 exit;
              }
              if($dfvl eq "") { 
                 printf "ERROR!! Row ".$cur_row.": Missing signal default value\n";
                 exit;
              }
}
##--------------------------------------------------------------------------------------------------

##--------------------------------------------------------------------------------------------------
sub check_first_address_err {
 if(($name ne "") and ($addr_no == 0)) {
     printf "ERROR!! Row ".$cur_row.": Missing address of the first found register\n";
     exit;
 }
}
##--------------------------------------------------------------------------------------------------






