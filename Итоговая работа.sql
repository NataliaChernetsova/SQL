--В каких городах больше одного аэропорта?

/* Вывести города из таблицы airports  
 сгруппировать по городу, где количество аэропортов больше 1 */

select (city->>'ru')::text city,  count(airport_code) count_airports     
from airports_data ad 
group by ad.city                              
having count(airport_code) > 1 

------------------------------------------------------------------------------------------

--В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?

/* Соединяем две таблицы flights и aircrafts_data по столбцу aircraft_code, 
 * подзапросом находим самолеты с максимальной дальностью, 
 * выводим уникальные аэропорты, где были такие самолеты */

 select distinct f.departure_airport
from flights f 
left join aircrafts_data ad using(aircraft_code)
where "range" = (select max("range") from aircrafts_data)

------------------------------------------------------------------------------------------


--Вывести 10 рейсов с максимальным временем задержки вылета

/*Выводим рейсы и время задержки(разница между фактическим временем вылета и планируемым), 
 * оставляем строки, где значение не null
 сортируем время задержки по убыванию 
 ограничиваемся 10ю строками*/


select flight_id, (f.actual_departure - f.scheduled_departure) delay_time
from flights f 
where (f.actual_departure - f.scheduled_departure) is not null 
order by delay_time desc 
limit 10

------------------------------------------------------------------------------------------

--Были ли брони, по которым не были получены посадочные талоны?

/*В подзапросе соединяем таблицы tickets и boarding_passes по столбцу ticket_no,  
 * выводим количество уникальных броней, где посадочные талоны  null.
 Вводим условное выражение из подзапроса, если количество броней нулевое, то все брони получили посадочные талоны,
 иначе, есть такие брони и указываем оператором конкатенации точное количество таких броней*/


select 
  (case
     when a.count_book_ref is null then 'По всем броням были получены пасадочные талоны'
     else 'Есть '|| count_book_ref ||' броней, по которым не были получены посадочные талоны'
     end) "Брони без посадочного талона"
from (
 	select 
 		count(distinct t.book_ref) as count_book_ref
	from tickets t
		left join boarding_passes bp using(ticket_no)
		where bp.boarding_no is null 
) as a

------------------------------------------------------------------------------------------
	
--Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете.
--Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров 
--из каждого аэропорта на каждый день. Т.е. в этом столбце должна отражаться накопительная сумма - 
--сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах за день.

	/*Для того, чтобы найти свободные места для каждого рейса, 
	 * соединяем таблицу flights по столбцу aircraft_code с 
	 подзапросом cs(находит общее количество мест в самолете seats_aicraft, группировка по aircraft_code),
	 и с подзапросом bp(находит количество занятых мест boarding_seats, группировка по рейсу flight_id).
	 У нас получается таблица из столбцов: рейс, общее количество мест в самолете по данному рейсу и количество занятых мест,
	 в select прописываем формулу для подсчета процента свободных мест.
	 В оконной функции суммируем количество занятых мест, группируем по фактической дате вылета и аэропорту, сортируем по актуальной дате вылета.
 */

select f.flight_id, round(((seats_aicraft-boarding_seats)::numeric/seats_aicraft)*100,2) percent_free_seats, 
	   f.departure_airport, 
	   date(f.actual_departure),
	   sum(bs.boarding_seats) over (partition by date(f.actual_departure), 
	   f.departure_airport  order by f.actual_departure range unbounded preceding)
from flights f
left join (
	select aircraft_code, count(seat_no) seats_aicraft
	from seats s
	group by aircraft_code) cs on f.aircraft_code = cs.aircraft_code
left join (
	select count(seat_no) boarding_seats, flight_id
	from boarding_passes bp
	group by flight_id) bs on bs.flight_id = f.flight_id
where boarding_seats is not null 

------------------------------------------------------------------------------------------

--Найдите процентное соотношение перелетов по типам самолетов от общего количества.

/*Группируем по aircraft_code, считаем в кажой группе количество рейсов, 
 * делим на подзапрос(общее количество рейсов) умножаем на 100,
 * округляем до двух знаков после запятой.*/


select aircraft_code,
	   round(count(flight_id)::numeric /(select count(flight_id)::numeric from flights)*100,2) percent_flight
from flights f
group by aircraft_code
order by percent_flight desc 

------------------------------------------------------------------------------------------

--Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?

/* Содаем два CTE: в первом находим минимальную стоимость перелета и группируем по flight_id,
 * во втором находим максимальную стоимость и группируем по flight_id, соединям два CTE по flight_id, 
 для получения городов потребуются таблицы flights и airports_data, присоединяем их по flight_id и airport_code соответственно,
 выводим города с условием: минимальная стоимость бизнес-класса меньше максимальной стоимости эконом-класса */


with business as (
	select flight_id, min(amount) b1
	from ticket_flights tf 
	where fare_conditions = 'Business'
	group by flight_id
	),
economy as (
    select flight_id, max(amount) e1
	from ticket_flights tf 
	where fare_conditions = 'Economy'
	group by flight_id
	)
select ad.city
from business
    join economy on business.flight_id = economy.flight_id 
	join flights f on  business.flight_id = f.flight_id 
    join airports_data ad on f.arrival_airport = ad.airport_code
where b1 < e1

------------------------------------------------------------------------------------------

--Между какими городами нет прямых рейсов?

/* создаю представление, где вывожу все возможные комбинации вылет-прилет,
 * с помощью оператора except из всех комбинаций убираю все фактические перелеты,
 и получаю города между которыми нет прямых рейсов */

create view direct_flights as (
	select (ad1.city->>'ru')::text from_city , 
	(ad2.city->>'ru')::text to_city
	from airports_data ad1, airports_data ad2
	where ad1.city->>'ru' != ad2.city->>'ru'
except
	select (ad1.city->>'ru')::text from_city , 
	(ad2.city->>'ru')::text to_city
	from flights f
		join airports_data ad1 on f.departure_airport = ad1.airport_code 
		join airports_data ad2 on f.arrival_airport = ad2.airport_code 
	where ad1.city->>'ru' != ad2.city->>'ru'
)

select *
from direct_flights

--Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной 
--дальностью перелетов  в самолетах, обслуживающих эти рейсы

/*создаю материальное представление для кодов аэропортов и их широты и долготы, разделяю на аэропорты вылета и аэропорты прилета,
соединив с таблицей  flights.
вычисляю по формуле расстояние между аэропортами
нахожу разность между максимальной дальностью и расстоянием между аэропортами 
с помощью case добавляю столбец, где указывается значение типа boolean, 
если  расстояние превышает допустимую дальности то true, иначе false.*/

create view cor as (
select f.aircraft_code, ad.airport_code as departure, 
ad2.airport_code as arrival, 
ad.coordinates[1] as latitude_dep, ad.coordinates[0] as longitide_dep,
ad2.coordinates[1] as latitude_arr, ad2.coordinates[0] as longitide_arr
from flights f 
join airports_data ad on f.departure_airport = ad.airport_code 
join airports_data ad2 on f.arrival_airport = ad2.airport_code 
group by ad.airport_code, ad2.airport_code, f.aircraft_code
)

select departure, arrival, cor.aircraft_code, a."range",
round((acos(sind(latitude_dep)*sind(latitude_arr)+cosd(latitude_dep)*cosd(latitude_arr)*cosd(longitide_dep-longitide_arr))*6371):: numeric, 2) distance,
a."range" - round((acos(sind(latitude_dep)*sind(latitude_arr)+cosd(latitude_dep)*cosd(latitude_arr)*cosd(longitide_dep-longitide_arr))*6371):: numeric, 2) difference,
case 
   when a."range" - round((acos(sind(latitude_dep)*sind(latitude_arr)+cosd(latitude_dep)*cosd(latitude_arr)*cosd(longitide_dep-longitide_arr))*6371):: numeric, 2) < 0 
   then true
   else false
end
 "deviation"
from cor 
join aircrafts_data a on a.aircraft_code = cor.aircraft_code


-- или c подзапросом в from 

select departure, arrival, a.aircraft_code, a."range",
round((acos(sind(latitude_dep)*sind(latitude_arr)+cosd(latitude_dep)*cosd(latitude_arr)*cosd(longitide_dep-longitide_arr))*6371):: numeric, 2) distance,
a."range" - round((acos(sind(latitude_dep)*sind(latitude_arr)+cosd(latitude_dep)*cosd(latitude_arr)*cosd(longitide_dep-longitide_arr))*6371):: numeric, 2) difference,
case 
   when a."range" - round((acos(sind(latitude_dep)*sind(latitude_arr)+cosd(latitude_dep)*cosd(latitude_arr)*cosd(longitide_dep-longitide_arr))*6371):: numeric, 2) < 0 
   then true
   else false
end "deviation"
from (
select distinct f.aircraft_code, ad.airport_code as departure, 
ad2.airport_code as arrival, a."range", 
ad.coordinates[1] as latitude_dep, ad.coordinates[0] as longitide_dep,
ad2.coordinates[1] as latitude_arr, ad2.coordinates[0] as longitide_arr
from flights f 
join airports_data ad on f.departure_airport = ad.airport_code 
join airports_data ad2 on f.arrival_airport = ad2.airport_code 
join aircrafts_data a on f.aircraft_code = a.aircraft_code
) a
order by difference asc
 



