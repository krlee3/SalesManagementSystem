create table customer(
	custid varchar(10) primary key,
	name varchar(20),
	phone varchar(15) unique not null,
	email varchar(20) unique not null,
	address varchar(20)
);

insert into customer values('c1','john','111-111-1111','john@email.com', '123 abc st');
insert into customer values('c2','amy','111-234-5111','amy@email.com', '345 abc st');
insert into customer values('c3','bob','123-456-7890','bob@email.com','456 def st');
insert into customer values('c4','eve','134-465-7890','eve@email.com','234 def st');

select * from customer;

create table goldcustomer(
	custid varchar(10) primary key references customer(custid),
	datejoined date
);

insert into goldcustomer values('c1','01-JAN-21');

select * from goldcustomer;

create table storeitems(
	itemid varchar(10) primary key,
	price number(6,2)
);

insert into storeitems values('s1', 5.99);
insert into storeitems values('s2', 7.69);
insert into storeitems values('s3', 10.49);
insert into storeitems values('s4', 11.99);
insert into storeitems values('s5', 80.99);

select * from storeitems;

create table comicbook(
	isbn int unique,
	title varchar(40),
	publishedDate date,
	no_of_copies int check(no_of_copies >= 0),
	itemid varchar(10) primary key references storeitems(itemid)
);

insert into comicbook values(1, 'Book 1', '10-JAN-20', 5, 's1');
insert into comicbook values(2, 'Book 2', '14-MAR-20', 7, 's2');
insert into comicbook values(3, 'Book 3', '14-MAR-20', 10, 's3');

select * from comicbook;

create table bookcopyno(
	isbn int,
	co_number int,
	primary key(isbn, co_number)
);

create or replace procedure assigncopyno (v_isbn in int)
is
i int := 1;
copies int;
begin
	select no_of_copies into copies from comicbook where isbn = v_isbn;
	while i <= copies loop
		insert into bookcopyno
		values(v_isbn, i);
		i := i + 1;
	end loop;
end;
/

exec assigncopyno(1)
exec assigncopyno(2)
exec assigncopyno(3)

select * from bookcopyno;

create table tshirt(
	shirt_size varchar(7),
	amount int,
	itemid varchar(10) primary key references storeitems(itemid)
);

insert into tshirt values('XS', 10, 's4');
insert into tshirt values('S', 10, 's5');

select * from tshirt;

create table itemorder(
	orderid varchar(30) primary key,
	custid varchar(10) references customer(custid),
	itemid varchar(10) references storeitems(itemid),
	date_of_order date,
	no_of_items int,
	shipped_date date,
	shipping_fee number(2)
);

create or replace procedure addItemOrder(order_id in varchar, item_id in varchar, customerid in varchar, date_ordered in date, number_ordered in int, shipped_date in date) is
copies comicbook.no_of_copies%type;
num_shirts tshirt.amount%type;
v_isbn int;
not_enough exception;
already_exist exception;
cursor c is select itemid from comicbook where itemid = item_id;
inum comicbook.itemid%type;
num int := number_ordered - 1;
begin
	-- check if orderid already exists
	for i in (select orderid from itemorder) loop
		if i.orderid = order_id then
			raise already_exist;
		end if;
	end loop;

	open c;
	fetch c into inum;
	if c%found then
		-- check if there are enough copies
		select no_of_copies into copies from comicbook where itemid = item_id;
		if number_ordered > copies then
			raise not_enough;
		end if;

		-- add order into itemorder
		insert into itemorder
		values(order_id, customerid, item_id, date_ordered, number_ordered, shipped_date, 10);

		-- check if customer is regular or gold
		for i in (select custid from goldcustomer where custid = customerid) loop
			update itemorder
			set shipping_fee = 0
			where custid = customerid;
		end loop;

		-- update no of copies in comicbook
		update comicbook
		set no_of_copies = no_of_copies - number_ordered
		where itemid = item_id;

		-- update no of copies in bookcopyno
		select isbn into v_isbn from comicbook where itemid = item_id;
		while num >= 0 loop
			delete from bookcopyno where isbn = v_isbn and co_number = copies - num;
			num := num - 1;
		end loop;

	elsif c%notfound then
		-- For tshirt
		-- check if there are enough
		select amount into num_shirts from tshirt where itemid = item_id;
		if number_ordered > num_shirts then
			raise not_enough;
		end if;

		-- update amount of tshirts in tshirt
		update tshirt
		set amount = amount - 1
		where itemid = item_id;

		-- add order into itemorder
		insert into itemorder
		values(order_id, customerid, item_id, date_ordered, number_ordered, shipped_date, 10);

		-- check if customer is regular or gold
		for i in (select custid from goldcustomer where custid = customerid) loop
			update itemorder
			set shipping_fee = 0
			where custid = customerid;
		end loop;
	end if;
exception
	when already_exist then
		raise_application_error(-20101, 'Orderid already exists');
	when not_enough then
		raise_application_error(-20101,'Not enough');
end;
/

exec additemorder('1','s1','c1','04-MAR-21',1,sysdate)
exec additemorder('2','s2','c2','05-MAR-21',2,null)
exec additemorder('3','s3','c3','01-MAR-21',10,null)
exec additemorder('4','s4','c4','28-FEB-21',5,'01-MAR-21')
exec additemorder('5','s5','c1','09-MAR-21',3,null)

select * from itemorder;
select * from comicbook;
select * from bookcopyno;
select * from tshirt;

create or replace trigger custTypeChange
after insert on goldcustomer
for each row
begin
	update itemorder
	set shipping_fee = 0
	where shipped_date is null and custid = :new.custid;
end;
/

create or replace procedure setShippingDate(v_orderid in varchar, new_shipping_date in date) as
begin
	update itemorder
	set shipped_date = new_shipping_date
	where orderid = v_orderid;
end;
/

exec setshippingdate('2', '09-MAR-21')
select * from itemorder;

insert into goldcustomer values('c2',sysdate);
insert into goldcustomer values('c3',sysdate);
select * from itemorder;

create or replace function computeTotal(v_orderid in varchar)
return number is
total number(6,2) := 0.00;
item_id itemorder.itemid%type;
number_items itemorder.no_of_items%type;
item_price number(6,2);
customerid itemorder.custid%type;
ship_fee itemorder.shipping_fee%type;
cursor c is select custid from goldcustomer;
begin
	-- Total of everything including 5% tax
	select itemid into item_id from itemorder where orderid = v_orderid;
	select price into item_price from storeitems where itemid = item_id;
	select no_of_items into number_items from itemorder where orderid = v_orderid;
	select shipping_fee into ship_fee from itemorder where orderid = v_orderid;
	total := item_price * number_items * 1.05;

	-- Check if customer is Regular or Gold

	for i in c loop
		select custid into customerid from itemorder where orderid = v_orderid;

		-- For Gold Customers
		if customerid = i.custid then
			if total >= 100 then
				total := total * 0.9;
			end if;
		end if;
	end loop;

	-- For Regular Customers
	total := total + ship_fee;

	return total;
end;
/

select computeTotal('1') from dual;
select computeTotal('2') from dual;
select computeTotal('3') from dual;
select computeTotal('4') from dual;
select computeTotal('5') from dual;


create or replace procedure showItemOrders(customerid in varchar, v_date in date) is
v_name customer.name%type;
v_phone customer.phone%type;
v_address customer.address%type;
v_orderid itemorder.orderid%type;
v_itemid storeitems.itemid%type;
v_itemname comicbook.title%type;
v_price storeitems.price%type;
v_shippeddate itemorder.shipped_date%type;
v_numberofitems itemorder.no_of_items%type;
v_total number(6,2);
v_tax number(5,2);
v_shippingfee itemorder.shipping_fee%type;
v_discount number(5,2) := 0;
v_grandtotal number(6,2);
begin
	-- Customer details
	select name, phone, address into v_name, v_phone, v_address from customer where custid = customerid;
	dbms_output.put_line('Customer Details:');
	dbms_output.put_line('Custid: ' ||  customerid);
	dbms_output.put_line('Name: ' || v_name);
	dbms_output.put_line('Phone: ' || v_phone);
	dbms_output.put_line('Address: ' || v_address);

	-- Order details
	select orderid, itemid, shipped_date into v_orderid, v_itemid, v_shippeddate from itemorder where custid = customerid and to_date(date_of_order, 'DD-MON-YY') = to_date(v_date, 'DD-MON-YY');
	select title into v_itemname from comicbook where itemid = v_itemid;
	select price into v_price from storeitems where itemid = v_itemid;
	dbms_output.put_line('Order Details:');
	dbms_output.put_line('Orderid: ' ||  v_orderid);
	dbms_output.put_line('Item Name: ' || v_itemname);
	dbms_output.put_line('Price: ' || v_price);
	dbms_output.put_line('Date Ordered: ' || v_date);
	dbms_output.put_line('Shipped Date: ' || v_shippeddate);

	-- Payment details
	select no_of_items into v_numberofitems from itemorder where orderid = v_orderid;
	v_total := v_price * v_numberofitems;
	v_tax := v_total * 0.05;
	select shipping_fee into v_shippingfee from itemorder where orderid = v_orderid;
	if v_shippingfee = 0 and v_total >= 100 then
		v_discount := v_total * 0.1;
	end if;
	select computeTotal(v_orderid) into v_grandtotal from dual;
	dbms_output.put_line('Payment Details:');
	dbms_output.put_line('Total for all items: ' ||  v_total);
	dbms_output.put_line('Tax: ' || v_tax);
	dbms_output.put_line('Shipping Fee: ' || v_shippingfee);
	dbms_output.put_line('Discount: ' || v_discount);
	dbms_output.put_line('Grand Total: ' || v_grandtotal);
end;
/

set serveroutput on
exec showitemorders('c2','05-MAR-21')
