# #=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger, Accounting
# Copyright (c) 1998-2003
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# Delivery orders
#======================================================================

use List::Util qw(max sum);
use POSIX qw(strftime);
use YAML;

use SL::DO;
use SL::IR;
use SL::IS;
use SL::ReportGenerator;
use SL::WH;

require "bin/mozilla/arap.pl";
require "bin/mozilla/common.pl";
require "bin/mozilla/invoice_io.pl";
require "bin/mozilla/io.pl";
require "bin/mozilla/reportgenerator.pl";

1;

# end of main

sub check_do_access {
  $auth->assert($form->{type} . '_edit');
}

sub set_headings {
  $lxdebug->enter_sub();

  check_do_access();

  my ($action) = @_;

  if ($form->{type} eq 'purchase_delivery_order') {
    $form->{vc}    = 'vendor';
    $form->{title} = $action eq "edit" ? $locale->text('Edit Purchase Delivery Order') : $locale->text('Add Purchase Delivery Order');
  } else {
    $form->{vc}    = 'customer';
    $form->{title} = $action eq "edit" ? $locale->text('Edit Sales Delivery Order') : $locale->text('Add Sales Delivery Order');
  }

  $form->{heading} = $locale->text('Delivery Order');

  $lxdebug->leave_sub();
}

sub add {
  $lxdebug->enter_sub();

  check_do_access();

  set_headings("add");

  $form->{callback} = build_std_url('action=add', 'type', 'vc') unless ($form->{callback});

  order_links();
  prepare_order();
  display_form();

  $lxdebug->leave_sub();
}

sub edit {
  $lxdebug->enter_sub();

  check_do_access();

  # show history button
  $form->{javascript} = qq|<script type="text/javascript" src="js/show_history.js"></script>|;
  #/show hhistory button

  $form->{simple_save} = 0;

  set_headings("edit");

  # editing without stuff to edit? try adding it first
  if ($form->{rowcount} && !$form->{print_and_save}) {
#     map { $id++ if $form->{"multi_id_$_"} } (1 .. $form->{rowcount});
#     if (!$id) {

      # reset rowcount
      undef $form->{rowcount};
      add();
      $lxdebug->leave_sub();
      return;
#     }
  } elsif (!$form->{id}) {
    add();
    $lxdebug->leave_sub();
    return;
  }

  if ($form->{print_and_save}) {
    $form->{action}   = "print";
    $form->{resubmit} = 1;
    $language_id      = $form->{language_id};
    $printer_id       = $form->{printer_id};
  }

  set_headings("edit");

  order_links();
  prepare_order();

  if ($form->{print_and_save}) {
    $form->{language_id} = $language_id;
    $form->{printer_id}  = $printer_id;
  }

  display_form();

  $lxdebug->leave_sub();
}

sub order_links {
  $lxdebug->enter_sub();

  check_do_access();

  # get customer/vendor
  $form->all_vc(\%myconfig, $form->{vc}, ($form->{vc} eq 'customer') ? "AR" : "AP");

  # retrieve order/quotation
  $form->{webdav}   = $webdav;
  $form->{jsscript} = 1;

  my $editing = $form->{id};

  DO->retrieve();

  $payment_id  = $form->{payment_id}  if ($form->{payment_id});
  $language_id = $form->{language_id} if ($form->{language_id});
  $taxzone_id  = $form->{taxzone_id}  if ($form->{taxzone_id});
  $salesman_id = $form->{salesman_id} if ($editing);


  $taxincluded    = $form->{taxincluded};
  $form->{shipto} = 1 if $form->{id};

  if ($form->{"all_$form->{vc}"}) {
    unless ($form->{"$form->{vc}_id"}) {
      $form->{"$form->{vc}_id"} = $form->{"all_$form->{vc}"}->[0]->{id};
    }
  }

  $cp_id    = $form->{cp_id};
  $intnotes = $form->{intnotes};

  $form->{cp_id} = $cp_id;

  $form->{payment_id}  = $payment_id  if ($payment_id);
  $form->{language_id} = $language_id if ($language_id);
  $form->{taxzone_id}  = $taxzone_id  if ($taxzone_id);
  $form->{intnotes}    = $intnotes    if ($intnotes);

  ($form->{ $form->{vc} })  = split /--/, $form->{ $form->{vc} };
  $form->{"old$form->{vc}"} = qq|$form->{$form->{vc}}--$form->{"$form->{vc}_id"}|;

  $form->{taxincluded} = $taxincluded if ($form->{id});

  $form->{employee} = "$form->{employee}--$form->{employee_id}";

  $form->{salesman_id} = $salesman_id if ($editing);

  $lxdebug->leave_sub();
}

sub prepare_order {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{formname} = $form->{type} unless $form->{formname};

  my $i = 0;
  foreach $ref (@{ $form->{form_details} }) {
    $form->{rowcount} = ++$i;

    map { $form->{"${_}_$i"} = $ref->{$_} } keys %{$ref};
  }
  for my $i (1 .. $form->{rowcount}) {
    if ($form->{id}) {
      $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"discount_$i"} * 100);
    } else {
      $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"discount_$i"});
    }
    ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
    $dec           = length $dec;
    $decimalplaces = ($dec > 2) ? $dec : 2;

    # copy reqdate from deliverydate for invoice -> order conversion
    $form->{"reqdate_$i"} = $form->{"deliverydate_$i"} unless $form->{"reqdate_$i"};

    $form->{"sellprice_$i"} = $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, $decimalplaces);

    (my $dec_qty) = ($form->{"qty_$i"} =~ /\.(\d+)/);
    $dec_qty = length $dec_qty;
    $form->{"qty_$i"} = $form->format_amount(\%myconfig, $form->{"qty_$i"}, $dec_qty);

    map { $form->{"${_}_$i"} =~ s/\"/&quot;/g } qw(partnumber description unit);
  }

  $lxdebug->leave_sub();
}

sub form_header {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{employee_id} = $form->{old_employee_id} if $form->{old_employee_id};
  $form->{salesman_id} = $form->{old_salesman_id} if $form->{old_salesman_id};

  # use JavaScript Calendar or not
  $form->{jsscript} = 1;

  #write Trigger
  $jsscript = Form->write_trigger(\%myconfig, "2", "transdate", "BL", "trigger1", "reqdate", "BL", "trigger2");

  my @old_project_ids = ($form->{"globalproject_id"});
  map({ push(@old_project_ids, $form->{"project_id_$_"})
          if ($form->{"project_id_$_"}); } (1..$form->{"rowcount"}));

  my $vc = $form->{vc} eq "customer" ? "customers" : "vendors";
  $form->get_lists("contacts"       => "ALL_CONTACTS",
                   "shipto"         => "ALL_SHIPTO",
                   "projects"       => {
                     "key"          => "ALL_PROJECTS",
                     "all"          => 0,
                     "old_id"       => \@old_project_ids
                   },
                   "employees"      => "ALL_EMPLOYEES",
                   "salesmen"       => "ALL_SALESMEN",
                   $vc              => "ALL_VC",
                   "price_factors"  => "ALL_PRICE_FACTORS",
                   "departments"    => "ALL_DEPARTMENTS",
                   "business_types" => "ALL_BUSINESS_TYPES",
    );

  map { $_->{value} = "$_->{description}--$_->{id}" } @{ $form->{ALL_DEPARTMENTS} };
  map { $_->{value} = "$_->{name}--$_->{id}"        } @{ $form->{ALL_VC} };

  $form->{SHOW_VC_DROP_DOWN} =  $myconfig{vclimit} > scalar @{ $form->{ALL_VC} };

  $form->{oldvcname}         =  $form->{"old$form->{vc}"};
  $form->{oldvcname}         =~ s/--.*//;

  $form->{onload} = "";
  if ($form->{resubmit}) {
    if ($form->{format} eq "html") {
      $form->{onload} = "window.open('about:blank','Beleg'); document.do.target = 'Beleg';";
    }
    $form->{onload} .= "document.do.submit();"
  }

  $form->header();
  print $form->parse_html_template('do/form_header');

  $lxdebug->leave_sub();
}

sub form_footer {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{PRINT_OPTIONS} = print_options('inline' => 1);

  print $form->parse_html_template('do/form_footer');

  $lxdebug->leave_sub();
}

sub update_delivery_order {
  $lxdebug->enter_sub();

  check_do_access();

  set_headings($form->{"id"} ? "edit" : "add");

  $form->{update} = 1;

  $payment_id = $form->{payment_id} if $form->{payment_id};

  check_name($form->{vc});

  $form->{payment_id} = $payment_id if $form->{payment_id} eq "";

  # for pricegroups
  $i = $form->{rowcount};

  if (   ($form->{"partnumber_$i"} eq "")
      && ($form->{"description_$i"} eq "")
      && ($form->{"partsgroup_$i"}  eq "")) {

    check_form();

  } else {

    if ($form->{type} eq 'purchase_delivery_order') {
      IR->retrieve_item(\%myconfig, $form);
    } else {
      IS->retrieve_item(\%myconfig, $form);
    }

    my $rows = scalar @{ $form->{item_list} };

    if ($rows) {
      $form->{"qty_$i"} = 1 unless ($form->{"qty_$i"});

      if ($rows > 1) {

        select_item();
        exit;

      } else {

        map { $form->{item_list}[$i]{$_} =~ s/\"/&quot;/g }    qw(partnumber description unit);
        map { $form->{"${_}_$i"} = $form->{item_list}[0]{$_} } keys %{ $form->{item_list}[0] };

        $form->{"marge_price_factor_$i"} = $form->{item_list}->[0]->{price_factor};
        $form->{"sellprice_$i"}          = $form->format_amount(\%myconfig, $form->{"sellprice_$i"});
        $form->{"qty_$i"}                = $form->format_amount(\%myconfig, $form->{"qty_$i"});
      }

      display_form();

    } else {

      # ok, so this is a new part
      # ask if it is a part or service item

      if (   $form->{"partsgroup_$i"}
          && ($form->{"partsnumber_$i"} eq "")
          && ($form->{"description_$i"} eq "")) {
        $form->{rowcount}--;
        $form->{"discount_$i"} = "";
        display_form();

      } else {
        $form->{"id_$i"}   = 0;
        new_item();
      }
    }
  }

  $lxdebug->leave_sub();
}

sub search {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{vc} = $form->{type} eq 'purchase_order' ? 'vendor' : 'customer';

  $form->get_lists("projects"     => { "key" => "ALL_PROJECTS",
                                       "all" => 1 },
                   "employees"    => "ALL_EMPLOYEES",
                   "salesmen"     => "ALL_SALESMEN",
                   "$form->{vc}s" => "ALL_VC");

  $form->{SHOW_VC_DROP_DOWN} =  $myconfig{vclimit} > scalar @{ $form->{ALL_VC} };
  $form->{jsscript}          = 1;
  $form->{title}             = $locale->text('Delivery Orders');

  $form->header();

  print $form->parse_html_template('do/search');

  $lxdebug->leave_sub();
}

sub orders {
  $lxdebug->enter_sub();

  check_do_access();

  ($form->{ $form->{vc} }, $form->{"${form->{vc}}_id"}) = split(/--/, $form->{ $form->{vc} });

  $form->{sort} ||= 'transdate';

  DO->transactions();

  $form->{rowcount} = scalar @{ $form->{DO} };

  my @columns = qw(
    transdate
    id                      donumber
    ordnumber
    name                    employee
    shipvia                 globalprojectnumber
    transaction_description
    open                    delivered
  );

  $form->{l_open}      = $form->{l_closed} = "Y" if ($form->{open}      && $form->{closed});
  $form->{l_delivered} = "Y"                     if ($form->{delivered} && $form->{notdelivered});

  $form->{title}       = $locale->text('Delivery Orders');

  my $attachment_basename = $form->{vc} eq 'vendor' ? $locale->text('purchase_delivery_order_list') : $locale->text('sales_delivery_order_list');

  my $report = SL::ReportGenerator->new(\%myconfig, $form);

  my @hidden_variables = map { "l_${_}" } @columns;
  push @hidden_variables, $form->{vc}, qw(l_closed l_notdelivered open closed delivered notdelivered donumber ordnumber
                                          transaction_description transdatefrom transdateto type vc employee_id salesman_id);

  my $href = build_std_url('action=orders', grep { $form->{$_} } @hidden_variables);

  my %column_defs = (
    'ids'                     => { 'text' => '', },
    'transdate'               => { 'text' => $locale->text('Date'), },
    'id'                      => { 'text' => $locale->text('ID'), },
    'donumber'                => { 'text' => $locale->text('Delivery Order'), },
    'ordnumber'               => { 'text' => $locale->text('Order'), },
    'name'                    => { 'text' => $form->{vc} eq 'customer' ? $locale->text('Customer') : $locale->text('Vendor'), },
    'employee'                => { 'text' => $locale->text('Salesperson'), },
    'shipvia'                 => { 'text' => $locale->text('Ship via'), },
    'globalprojectnumber'     => { 'text' => $locale->text('Project Number'), },
    'transaction_description' => { 'text' => $locale->text('Transaction description'), },
    'open'                    => { 'text' => $locale->text('Open'), },
    'delivered'               => { 'text' => $locale->text('Delivered'), },
  );

  foreach my $name (qw(id transdate donumber ordnumber name employee shipvia)) {
    $column_defs{$name}->{link} = $href . "&sort=$name";
  }

  $form->{"l_type"} = "Y";
  map { $column_defs{$_}->{visible} = $form->{"l_${_}"} ? 1 : 0 } @columns;
  $column_defs{ids}->{visible} = $allow_multiple_orders ? 'HTML' : 0;

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);

  $report->set_export_options('orders', @hidden_variables);

  $report->set_sort_indicator($form->{sort}, 1);

  my @options;
  if ($form->{customer}) {
    push @options, $locale->text('Customer') . " : $form->{customer}";
  }
  if ($form->{vendor}) {
    push @options, $locale->text('Vendor') . " : $form->{vendor}";
  }
  if ($form->{department}) {
    ($department) = split /--/, $form->{department};
    push @options, $locale->text('Department') . " : $department";
  }
  if ($form->{donumber}) {
    push @options, $locale->text('Delivery Order Number') . " : $form->{donumber}";
  }
  if ($form->{ordnumber}) {
    push @options, $locale->text('Order Number') . " : $form->{ordnumber}";
  }
  if ($form->{transaction_description}) {
    push @options, $locale->text('Transaction description') . " : $form->{transaction_description}";
  }
  if ($form->{transdatefrom}) {
    push @options, $locale->text('From') . "&nbsp;" . $locale->date(\%myconfig, $form->{transdatefrom}, 1);
  }
  if ($form->{transdateto}) {
    push @options, $locale->text('Bis') . "&nbsp;" . $locale->date(\%myconfig, $form->{transdateto}, 1);
  }
  if ($form->{open}) {
    push @options, $locale->text('Open');
  }
  if ($form->{closed}) {
    push @options, $locale->text('Closed');
  }
  if ($form->{delivered}) {
    push @options, $locale->text('Delivered');
  }
  if ($form->{notdelivered}) {
    push @options, $locale->text('Not delivered');
  }

  $report->set_options('top_info_text'       => join("\n", @options),
                       'output_format'       => 'HTML',
                       'title'               => $form->{title},
                       'attachment_basename' => $attachment_basename . strftime('_%Y%m%d', localtime time),
    );
  $report->set_options_from_form();

  # add sort and escape callback, this one we use for the add sub
  $form->{callback} = $href .= "&sort=$form->{sort}";

  # escape callback for href
  $callback = $form->escape($href);

  my $edit_url       = build_std_url('action=edit', 'type', 'vc');
  my $edit_order_url = build_std_url('script=oe.pl', 'type=' . ($form->{type} eq 'sales_delivery_order' ? 'sales_order' : 'purchase_order'), 'action=edit');

  foreach $dord (@{ $form->{DO} }) {
    $dord->{open}      = $dord->{closed}    ? $locale->text('No')  : $locale->text('Yes');
    $dord->{delivered} = $dord->{delivered} ? $locale->text('Yes') : $locale->text('No');

    my $row = { map { $_ => { 'data' => $dord->{$_} } } @columns };

    $row->{donumber}->{link}  = $edit_url       . "&id=" . E($dord->{id})      . "&callback=${callback}";
    $row->{ordnumber}->{link} = $edit_order_url . "&id=" . E($dord->{oe_id})   . "&callback=${callback}";

    $report->add_data($row);
  }

  $report->generate_with_headers();

  $lxdebug->leave_sub();
}

sub save {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  $form->isblank("transdate", $locale->text('Delivery Order Date missing!'));

  $form->{donumber} =~ s/^\s*//g;
  $form->{donumber} =~ s/\s*$//g;

  $msg = ucfirst $form->{vc};
  $form->isblank($form->{vc}, $locale->text($msg . " missing!"));

  # $locale->text('Customer missing!');
  # $locale->text('Vendor missing!');

  validate_items();

  # if the name changed get new values
  if (check_name($form->{vc})) {
    update();
    exit;
  }

  $form->{id} = 0 if $form->{saveasnew};

  DO->save();

  # saving the history
  if(!exists $form->{addition}) {
    $form->{snumbers} = qq|donumber_| . $form->{donumber};
  	$form->{addition} = "SAVED";
  	$form->save_history($form->dbconnect(\%myconfig));
  }
  # /saving the history

  $form->{simple_save} = 1;
  if(!$form->{print_and_save}) {
    set_headings("edit");
    update();
    exit;
  }
  $lxdebug->leave_sub();
}

sub delete {
  $lxdebug->enter_sub();

  check_do_access();

  map { delete $form->{$_} } qw(action header login password);
  my @variables = map { { 'key' => $_, 'value' => $form->{$_} } } grep { '' eq ref $form->{$_} } keys %{ $form };

  $form->{title} = $locale->text('Delete delivery order');
  $form->header();

  print $form->parse_html_template('do/delete', { 'VARIABLES' => \@variables });

  $lxdebug->leave_sub();
}

sub delete_delivery_order {
  $lxdebug->enter_sub();

  check_do_access();

  if (DO->delete()) {
    # saving the history
    if(!exists $form->{addition}) {
      $form->{snumbers} = qq|donumber_| . $form->{donumber};
  	  $form->{addition} = "DELETED";
  	  $form->save_history($form->dbconnect(\%myconfig));
    }
    # /saving the history

    $form->info($locale->text('Delivery Order deleted!'));
    exit();
  }

  $form->error($locale->text('Cannot delete delivery order!'));

  $lxdebug->leave_sub();
}

sub invoice {
  $lxdebug->enter_sub();

  check_do_access();
  $auth->assert($form->{type} eq 'purchase_order' || $form->{type} eq 'request_quotation' ? 'vendor_invoice_edit' : 'invoice_edit');

  $form->{deliverydate} = $form->{transdate};
  $form->{transdate}    = $form->{invdate} = $form->current_date(\%myconfig);
  $form->{duedate}      = $form->current_date(\%myconfig, $form->{invdate}, $form->{terms} * 1);

  $form->{id}     = '';
  $form->{closed} = 0;
  $form->{rowcount}--;

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  if ($form->{type} eq 'purchase_delivery_order') {
    $form->{title}  = $locale->text('Add Vendor Invoice');
    $form->{script} = 'ir.pl';
    $script         = "ir";

  } else {
    $form->{title}  = $locale->text('Add Sales Invoice');
    $form->{script} = 'is.pl';
    $script         = "is";
    $buysell        = 'buy';
  }

  for $i (1 .. $form->{rowcount}) {
    map { $form->{"${_}_${i}"} = $form->parse_amount(\%myconfig, $form->{"${_}_${i}"}) if $form->{"${_}_${i}"} } qw(ship qty sellprice listprice basefactor);
  }

  $form->{type} = "invoice";

  # locale messages
  $locale = new Locale "$myconfig{countrycode}", "$script";

  require "bin/mozilla/$form->{script}";

  my $currency = $form->{currency};
  invoice_links();

  $form->{currency}     = $currency;
  $form->{exchangerate} = "";
  $form->{forex}        = ($exchangerate = $form->check_exchangerate(\%myconfig, $form->{currency}, $form->{invdate}, $buysell));
  $form->{exchangerate} = $exchangerate if ($form->{forex});

  prepare_invoice();

  # format amounts
  for $i (1 .. $form->{rowcount}) {
    $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"discount_$i"});

    ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
    $dec           = length $dec;
    $decimalplaces = ($dec > 2) ? $dec : 2;

    # copy delivery date from reqdate for order -> invoice conversion
    $form->{"deliverydate_$i"} = $form->{"reqdate_$i"}
      unless $form->{"deliverydate_$i"};

    $form->{"sellprice_$i"} =
      $form->format_amount(\%myconfig, $form->{"sellprice_$i"},
                           $decimalplaces);

    (my $dec_qty) = ($form->{"qty_$i"} =~ /\.(\d+)/);
    $dec_qty = length $dec_qty;
    $form->{"qty_$i"} =
      $form->format_amount(\%myconfig, $form->{"qty_$i"}, $dec_qty);

  }

  display_form();

  $lxdebug->leave_sub();
}

sub save_as_new {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{saveasnew} = 1;
  $form->{closed}    = 0;
  map { delete $form->{$_} } qw(printed emailed queued);

  # Let Lx-Office assign a new order number if the user hasn't changed the
  # previous one. If it has been changed manually then use it as-is.
  $form->{donumber} =~ s/^\s*//g;
  $form->{donumber} =~ s/\s*$//g;
  if ($form->{saved_donumber} && ($form->{saved_donumber} eq $form->{donumber})) {
    delete($form->{donumber});
  }

  save();

  $lxdebug->leave_sub();
}

sub e_mail {
  $lxdebug->enter_sub();

  check_do_access();

  $form->{print_and_save} = 1;

  $print_post = 1;

  my $saved_form = save_form();

  save();

  restore_form($saved_form, 0, qw(id ordnumber quonumber));

  edit_e_mail();

  $lxdebug->leave_sub();
}

sub calculate_stock_in_out {
  $lxdebug->enter_sub();

  my $i = shift;

  if (!$form->{"id_${i}"}) {
    $lxdebug->leave_sub();
    return '';
  }

  my $in_out   = $form->{type} =~ /^sales/ ? 'out' : 'in';
  my $sinfo    = DO->unpack_stock_information('packed' => $form->{"stock_${in_out}_${i}"});

  my $sum      = AM->sum_with_unit(map { $_->{qty}, $_->{unit} } @{ $sinfo });

  my $content  = $form->format_amount_units('amount'      => $sum * 1,
                                            'part_unit'   => $form->{"partunit_$i"},
                                            'amount_unit' => $units->{$form->{"partunit_$i"}}->{base_unit},
                                            'conv_units'  => 'convertible_not_smaller',
                                            'max_places'  => 2);
  $content    .= qq| <input type="button" onclick="open_stock_in_out_window('${in_out}', $i);" value="?">|;

  $lxdebug->leave_sub();

  return $content;
}

sub get_basic_bin_wh_info {
  $lxdebug->enter_sub();

  my $stock_info = shift;

  foreach my $sinfo (@{ $stock_info }) {
    next unless ($sinfo->{bin_id});

    my $bin_info = WH->get_basic_bin_info('id' => $sinfo->{bin_id});
    map { $sinfo->{"${_}_description"} = $sinfo->{"${_}description"} = $bin_info->{"${_}_description"} } qw(bin warehouse);
  }

  $lxdebug->leave_sub();
}

sub stock_in_out_form {
  $lxdebug->enter_sub();

  if ($form->{in_out} eq 'out') {
    stock_out_form();
  } else {
    stock_in_form();
  }

  $lxdebug->leave_sub();
}

sub redo_stock_info {
  $lxdebug->enter_sub();

  my %params    = @_;

  my @non_empty = grep { $_->{qty} } @{ $params{stock_info} };

  if ($params{add_empty_row}) {
    push @non_empty, {
      'warehouse_id' => scalar(@non_empty) ? $non_empty[-1]->{warehouse_id} : undef,
      'bin_id'       => scalar(@non_empty) ? $non_empty[-1]->{bin_id}       : undef,
    };
  }

  @{ $params{stock_info} } = @non_empty;

  $lxdebug->leave_sub();
}

sub update_stock_in {
  $lxdebug->enter_sub();

  my $stock_info = [];

  foreach my $i (1..$form->{rowcount}) {
    push @{ $stock_info }, { map { $_ => $form->{"${_}_${i}"} } qw(warehouse_id bin_id chargenumber qty unit) };
  }
  $main::lxdebug->dump(0, "si", $stock_info);

  display_stock_in_form($stock_info);

  $lxdebug->leave_sub();
}

sub stock_in_form {
  $lxdebug->enter_sub();

  my $stock_info = DO->unpack_stock_information('packed' => $form->{stock});

  display_stock_in_form($stock_info);

  $lxdebug->leave_sub();
}

sub display_stock_in_form {
  $lxdebug->enter_sub();

  my $stock_info = shift;

  $form->{title} = $locale->text('Stock');

  my $part_info  = IC->get_basic_part_info('id' => $form->{parts_id});

  my $units      = AM->retrieve_units(\%myconfig, $form, "dimension");
  my $units_data = AM->unit_select_data($units, undef, undef, $part_info->{unit});

  my $access     = $auth->check_right($form->{login}, 'all_warehouses') ? undef : $form->{login};

  $form->get_lists('warehouses' => { 'key'    => 'WAREHOUSES',
                                     'bins'   => 'BINS',
                                     'access' => $access, });

  redo_stock_info('stock_info' => $stock_info, 'add_empty_row' => !$form->{closed});

  get_basic_bin_wh_info($stock_info);

  $form->header();
  print $form->parse_html_template('do/stock_in_form', { 'UNITS'      => $units_data,
                                                         'STOCK_INFO' => $stock_info,
                                                         'PART_INFO'  => $part_info, });

  $lxdebug->leave_sub();
}

sub set_stock_in {
  $lxdebug->enter_sub();

  my $stock_info = [];

  foreach my $i (1..$form->{rowcount}) {
    $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});

    next if ($form->{"qty_$i"} <= 0);

    push @{ $stock_info }, { map { $_ => $form->{"${_}_${i}"} } qw(warehouse_id bin_id chargenumber qty unit) };
  }

  $form->{stock} = YAML::Dump($stock_info);

  $form->header();
  print $form->parse_html_template('do/set_stock_in_out');

  $lxdebug->leave_sub();
}

sub stock_out_form {
  $lxdebug->enter_sub();

  $form->{title} = $locale->text('Release From Stock');

  my $part_info  = IC->get_basic_part_info('id' => $form->{parts_id});

  my $units      = AM->retrieve_units(\%myconfig, $form, "dimension");
  my $units_data = AM->unit_select_data($units, undef, undef, $part_info->{unit});

  my @contents   = DO->get_item_availability('parts_id' => $form->{parts_id});

  my $stock_info = DO->unpack_stock_information('packed' => $form->{stock});

  if (!$form->{closed}) {
    foreach my $row (@contents) {
      $row->{available_qty} = $form->format_amount_units('amount'      => $row->{qty} * 1,
                                                         'part_unit'   => $part_info->{unit},
                                                         'conv_units'  => 'convertible_not_smaller',
                                                         'max_places'  => 2);

      foreach my $sinfo (@{ $stock_info }) {
        next if (($row->{bin_id}       != $sinfo->{bin_id}) ||
                 ($row->{warehouse_id} != $sinfo->{warehouse_id}) ||
                 ($row->{chargenumber} ne $sinfo->{chargenumber}));

        map { $row->{"stock_$_"} = $sinfo->{$_} } qw(qty unit error);
      }
    }

  } else {
    get_basic_bin_wh_info($stock_info);

    foreach my $sinfo (@{ $stock_info }) {
      map { $sinfo->{"stock_$_"} = $sinfo->{$_} } qw(qty unit);
    }
  }

  $form->header();
  print $form->parse_html_template('do/stock_out_form', { 'UNITS'      => $units_data,
                                                          'WHCONTENTS' => $form->{closed} ? $stock_info : \@contents,
                                                          'PART_INFO'  => $part_info, });

  $lxdebug->leave_sub();
}

sub set_stock_out {
  $lxdebug->enter_sub();

  my $stock_info = [];

  foreach my $i (1 .. $form->{rowcount}) {
    $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});

    next if ($form->{"qty_$i"} <= 0);

    push @{ $stock_info }, {
      'warehouse_id' => $form->{"warehouse_id_$i"},
      'bin_id'       => $form->{"bin_id_$i"},
      'chargenumber' => $form->{"chargenumber_$i"},
      'qty'          => $form->{"qty_$i"},
      'unit'         => $form->{"unit_$i"},
      'row'          => $i,
    };
  }

  my @errors     = DO->check_stock_availability('requests' => $stock_info,
                                                'parts_id' => $form->{parts_id});

  $form->{stock} = YAML::Dump($stock_info);

  if (@errors) {
    $form->{ERRORS} = [];
    map { push @{ $form->{ERRORS} }, $locale->text('Error in row #1: The quantity you entered is bigger than the stocked quantity.', $_->{row}); } @errors;
    stock_in_out_form();

  } else {
    $form->header();
    print $form->parse_html_template('do/set_stock_in_out');
  }

  $lxdebug->leave_sub();
}

sub transfer_in_and_close {
  $lxdebug->enter_sub();

  my @part_ids = map { $form->{"id_${_}"} } grep { $form->{"id_${_}"} && $form->{"stock_in_${_}"} } (1 .. $form->{rowcount});
  my @all_requests;

  if (@part_ids) {
    my $units         = AM->retrieve_units(\%myconfig, $form, "dimension");
    my %part_info_map = IC->get_basic_part_info('id' => \@part_ids);
    my %request_map;

    $form->{ERRORS}   = [];

    foreach my $i (1 .. $form->{rowcount}) {
      next unless ($form->{"id_$i"} && $form->{"stock_in_$i"});

      my $row_sum_base_qty = 0;
      my $base_unit_factor = $units->{ $part_info_map{$form->{"id_$i"}}->{unit} }->{factor} || 1;

      foreach my $request (@{ DO->unpack_stock_information('packed' => $form->{"stock_in_$i"}) }) {
        $request->{parts_id}  = $form->{"id_$i"};
        $row_sum_base_qty    += $request->{qty} * $units->{$request->{unit}}->{factor} / $base_unit_factor;

        push @all_requests, $request;
      }

      next if (0 == $row_sum_base_qty);

      my $do_base_qty = $form->parse_amount(\%myconfig, $form->{"qty_$i"}) * $units->{$form->{"unit_$i"}}->{factor} / $base_unit_factor;

      if ($do_base_qty != $row_sum_base_qty) {
        push @{ $form->{ERRORS} }, $locale->text('Error in position #1: You must either assign no stock at all or the full quantity of #2 #3.',
                                                 $i, $form->{"qty_$i"}, $form->{"unit_$i"});
      }
    }

    if (@{ $form->{ERRORS} }) {
      push @{ $form->{ERRORS} }, $locale->text('The delivery order has not been closed. The warehouse contents have not changed.');

      update();
      $lxdebug->leave_sub();

      exit 0;
    }
  }

  DO->transfer_in_out('direction' => 'in',
                      'requests'  => \@all_requests);

  $form->{closed}    = 1;
  $form->{delivered} = 1;

  save();

  $lxdebug->leave_sub();
}

sub transfer_out_and_close {
  $lxdebug->enter_sub();

  my @part_ids = map { $form->{"id_${_}"} } grep { $form->{"id_${_}"} && $form->{"stock_out_${_}"} } (1 .. $form->{rowcount});
  my @all_requests;

  if (@part_ids) {
    my $units         = AM->retrieve_units(\%myconfig, $form, "dimension");
    my %part_info_map = IC->get_basic_part_info('id' => \@part_ids);
    my %request_map;

    $form->{ERRORS}   = [];

    foreach my $i (1 .. $form->{rowcount}) {
      next unless ($form->{"id_$i"} && $form->{"stock_out_$i"});

      my $row_sum_base_qty = 0;
      my $base_unit_factor = $units->{ $part_info_map{$form->{"id_$i"}}->{unit} }->{factor} || 1;

      foreach my $request (@{ DO->unpack_stock_information('packed' => $form->{"stock_out_$i"}) }) {
        $request->{parts_id} = $form->{"id_$i"};
        $request->{base_qty} = $request->{qty} * $units->{$request->{unit}}->{factor} / $base_unit_factor;

        my $map_key          = join '--', ($form->{"id_$i"}, @{$request}{qw(warehouse_id bin_id chargenumber)});

        $request_map{$map_key}                 ||= $request;
        $request_map{$map_key}->{sum_base_qty} ||= 0;
        $request_map{$map_key}->{sum_base_qty}  += $request->{base_qty};
        $row_sum_base_qty                       += $request->{base_qty};

        push @all_requests, $request;
      }

      next if (0 == $row_sum_base_qty);

      my $do_base_qty = $form->parse_amount(\%myconfig, $form->{"qty_$i"}) * $units->{$form->{"unit_$i"}}->{factor} / $base_unit_factor;

      if ($do_base_qty != $row_sum_base_qty) {
        push @{ $form->{ERRORS} }, $locale->text('Error in position #1: You must either assign no transfer at all or the full quantity of #2 #3.',
                                                 $i, $form->{"qty_$i"}, $form->{"unit_$i"});
      }
    }

    if (%request_map) {
      my @bin_ids      = map { $_->{bin_id} } values %request_map;
      my %bin_info_map = WH->get_basic_bin_info('id' => \@bin_ids);
      my @contents     = DO->get_item_availability('parts_id' => \@part_ids);

      foreach my $inv (@contents) {
        my $map_key = join '--', @{$inv}{qw(parts_id warehouse_id bin_id chargenumber)};

        next unless ($request_map{$map_key});

        my $request    = $request_map{$map_key};
        $request->{ok} = $request->{sum_base_qty} <= $inv->{qty};
      }

      foreach $request (values %request_map) {
        next if ($request->{ok});

        my $pinfo = $part_info_map{$request->{parts_id}};
        my $binfo = $bin_info_map{$request->{bin_id}};

        push @{ $form->{ERRORS} }, $locale->text("There is not enough available of '#1' at warehouse '#2', bin '#3', #4, for the transfer of #5.",
                                                 $pinfo->{description}, $binfo->{warehouse_description}, $binfo->{bin_description},
                                                 $request->{chargenumber} ? $locale->text('chargenumber #1', $request->{chargenumber}) : $locale->text('no chargenumber'),
                                                 $form->format_amount_units('amount'      => $request->{sum_base_qty},
                                                                            'part_unit'   => $pinfo->{unit},
                                                                            'conv_units'  => 'convertible_not_smaller'));
      }
    }

    if (@{ $form->{ERRORS} }) {
      push @{ $form->{ERRORS} }, $locale->text('The delivery order has not been closed. The warehouse contents have not changed.');

      update();
      $lxdebug->leave_sub();

      exit 0;
    }
  }

  DO->transfer_in_out('direction' => 'out',
                      'requests'  => \@all_requests);

  $form->{closed}    = 1;
  $form->{delivered} = 1;

  save();

  $lxdebug->leave_sub();
}

sub yes {
  call_sub($form->{yes_nextsub});
}

sub no {
  call_sub($form->{no_nextsub});
}

sub update {
  call_sub($form->{update_nextsub} || $form->{nextsub} || 'update_delivery_order');
}