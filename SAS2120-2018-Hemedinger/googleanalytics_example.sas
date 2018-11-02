/* Copyright 2017 SAS Institute */
/* Author: Chris Hemedinger     */
/* http://blogs.sas.com/content/sasdummy/using-sas-to-access-google-analytics-apis/ */
/* PREREQUISITES */
/* Use the Google Developer console to define a project                  */
/* and application, and generate a client-id and client-secret token     */
/* Of course, you'll need access to a Google Analytics account with at   */
/* least one view profile that allows access to metrics and dimensions.  */

/* STEP 1. Need to perform just once in a BROWSER.                            */
/* To authorize: Use the following URL while logged into your Google account  */
/* You will be prompted to allow the "app" access to your GA data (read only) */
/* Then, you'll be redirected to a web page with an auth code               */
/* That code value must be used as the "code_given" macro variable          */
/* Setting the redirect_uri like so is SUPER IMPORTANT:                     */
/*   redirect_uri=urn:ietf:wg:oauth:2.0:oob                                 */
/* Otherwise the API won't generate a code that you can use in a tool-based */
/* app like SAS                                                             */
/* URL is displayed here on multiple lines for readability, but you'll need */
/* it to be all on one line in the browser address bar.                     */

/* https://accounts.google.com/o/oauth2/v2/auth?
         scope=https://www.googleapis.com/auth/analytics.readonly
         &redirect_uri=urn:ietf:wg:oauth:2.0:oob
         &response_type=code
         &client_id=<your-client-id>.apps.googleusercontent.com 
*/

/* STEP 2. Need to perform just once by running in SAS.                     */
/* Next, run this step with the POST method to exchange that auth code for  */
/* an access token.  It will return a JSON with a valid Bearer access token */
/* That token expires 3600 seconds (1 hour)                                 */
/* It also returns a refresh_token, which you can exchange again for a new  */
/* access token after the first one expires                                 */
/* The refresh token never expires (though it can be revoked via console or */
/* API                                                                      */

/* You're running this just once to get the access token; after that, use   */
/* the refresh token to get a fresh one on subsequent runs                  */
/* Direct the "token" fileref to a place that you can read and save.        */
/*
filename token "c:\temp\token.json";
%let code_given =<code-returned-from-step-1> ;
%let oauth2=https://www.googleapis.com/oauth2/v4/token;
%let client_id=<your-client-id>.apps.googleusercontent.com;
%let client_secret=	<your-client-secret>;
proc http
 url="&oauth2.?client_id=&client_id.%str(&)code=&code_given.%str(&)client_secret=&client_secret.%str(&)redirect_uri=urn:ietf:wg:oauth:2.0:oob%str(&)grant_type=authorization_code%str(&)response_type=token"
 method="POST"
 out=token
;
run;
*/

/* NOTE: the refresh token and client-id/secret should be PROTECTED. */
/* Anyone who has access to these can get your GA data as if they    */
/* were you.                                                         */


/* STEP 3. Do this every time you want to use the GA API */
/* Turn in a refresh-token for a valid access-token      */
/* Should be good for 60 minutes                         */
/* So typically run once at beginning of the job.        */
%let oauth2=https://www.googleapis.com/oauth2/v4/token;
%let client_id=<your-client-id>.apps.googleusercontent.com;
%let client_secret=	<your-client-secret>;
%let refresh_token=<refresh-token-from-step-2>;

filename rtoken temp;
proc http
 method="POST"
 url="&oauth2.?client_id=&client_id.%str(&)client_secret=&client_secret.%str(&)grant_type=refresh_token%str(&)refresh_token=&refresh_token."
 out=rtoken;
run;

/* Read the access token out of the refresh response  */
/* Relies on the JSON libname engine (9.4m4 or later) */
libname rtok json fileref=rtoken;
data _null_;
 set rtok.root;
 call symputx('access_token',access_token);
run;

/* STEP 4. Finally, use the GA API to get some data!      */

/* In this scenario, we are fetching the daily page-level */
/* metrics for a range of dates, so making one API call   */
/* per day in the range                                   */
/* Set the start date and enddate so we know which days to fetch  */
%let startdate=%sysevalf('30Jan2017'd);
%let enddate = %sysfunc(today());

/* Metrics and dimensions are defined in the Google Analytics doc */
/* Experiment in the developer console for the right mix          */
/* Your scenario might be different and would require a different */
/* type of query                                                  */
/* The GA API will "number" the return elements as                */
/* element1, element2, element3 and so on                         */
/* In my example, path and title will be 1 and 2 */
%let dimensions=  %sysfunc(urlencode(%str(ga:pagePath,ga:pageTitle)));
/* then pageviews, uniquepageviews, timeonpage will be 3, 4, 5, etc. */
%let metrics=     %sysfunc(urlencode(%str(ga:pageviews,ga:uniquePageviews,ga:timeOnPage,ga:entrances,ga:exits)));
/* this ID is the "View ID" for the GA data you want to access   */
%let id=          %sysfunc(urlencode(%str(ga:<your-view-ID>)));

%macro getGAdata;
%do workdate = &enddate %to &startdate %by -1;
	%let urldate=%sysfunc(putn(&workdate.,yymmdd10.));
	filename ga_resp temp;
	proc http
	 url="https://www.googleapis.com/analytics/v3/data/ga?ids=&id.%str(&)start-date=&urldate.%str(&)end-date=&urldate.%str(&)metrics=&metrics.%str(&)dimensions=&dimensions.%str(&)max-results=20000"
	 method="GET" out=ga_resp;
	 headers 
	   "Authorization"="Bearer &access_token."
	   "client-id:"="&client_id.";
	run;

	libname garesp json fileref=ga_resp;

	data ga.ga_daily%sysfunc(compress(&urldate.,'-')) (drop=element:);
		set garesp.rows;
		drop ordinal_root ordinal_rows;
		length date 8 url $ 300 title $ 250 
	          views 8 unique_views 8 time_on_page 8 entrances 8 exits 8
	          ;
		format date yymmdd10.;
		date=&workdate.;
		/* Corerce the elements into data variables */
		/* Basic on expected sequence               */
		url = element1;
		title = element2;
		views = input(element3, 5.);
		unique_views = input(element4, 6.);
		time_on_page=input(element5, 7.2);
		entrances = input(element6, 6.);
		exits = input(element7, 6.);
	run;
%end;
%mend;

%getGAdata;

/* Assemble the daily files into one data set */
data alldays_gadata;
  set ga.ga_daily:;
run;
