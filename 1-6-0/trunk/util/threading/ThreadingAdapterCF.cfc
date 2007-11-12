<!---
License:
Copyright 2007 GreatBizTools, LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Copyright: GreatBizTools, LLC
Author: Peter J. Farrell (peter@mach-ii.com)
$Id: MessageHandler.cfc 549 2007-11-11 22:19:47Z peterfarrell $

Created version: 1.6.0
Updated version: 1.6.0

Notes:
--->
<cfcomponent displayname="ThreadingAdapter"
	extends="MachII.util.threading.ThreadingAdapter"
	output="false"
	hint="Threading adapter for Adobe ColdFusion 8+.">

	<!---
	PROPERTIES
	--->
	
	<!---
	INITIALIZATION / CONFIGURATION
	--->
	<cffunction name="init" access="public" returntype="ThreadingAdapter" output="false"
		hint="This initializes the adapter for Adobe ColdFusion 8+.">
		<cfreturn this />
	</cffunction>
	
	<!---
	PUBLIC FUNCTIONS
	--->
	<cffunction name="run" access="public" returntype="void" output="false"
		hint="Runs a thread.">
		<cfargument name="threadIds" type="struct" required="true" />
		<cfargument name="callback" type="any" required="true" />
		<cfargument name="method" type="string" required="true" />
		<cfargument name="parameters" type="struct" required="true" />
		<cfargument name="waitForThreads" type="boolean" required="true" />
		
		<cfset var threadId = createThreadId() />
		<cfset var collection = { action="run"
									, name=threadId
									, threadId=threadId
									, waitForThreads=waitForThreads } />
		
		<cfset arguments.threadIds[threadId] = "" />
		
		<!--- cfthread duplicates all passed attributes (we do not want to pass a copy of the even to the thread) --->
		<cfset request._MachIIThreadingAdapter[threadId] = StructNew() />
		<cfset request._MachIIThreadingAdapter[threadId].callback = arguments.callback />
		<cfset request._MachIIThreadingAdapter[threadId].method = arguments.method />
		<cfset request._MachIIThreadingAdapter[threadId].parameters = arguments.parameters />
		
		<!--- Run the thread and catch any errors for later --->
		<cfthread attributeCollection="#collection#">
			<cftry>
				<cfinvoke component="#request._MachIIThreadingAdapter[threadId].callback#"
					method="#request._MachIIThreadingAdapter[threadId].method#"
					argumentcollection="#request._MachIIThreadingAdapter[threadId].parameters#" />
					
				<cfcatch type="any">
					<!--- If we're going to join later, then save the exception --->
					<cfif waitForThreads>
						<cfset thread.caughtException = cfcatch />
					<!--- Otherwise, rethrow so this will be logged --->
					<cfelse>
						<cfrethrow />
					</cfif>
				</cfcatch>
			</cftry>
		</cfthread>
	</cffunction>
	
	<cffunction name="join" access="public" returntype="void" output="false"
		hint="Joins a group of threads.">
		<cfargument name="threadIds" type="struct" required="true" />
		<cfargument name="timeout" type="numeric" required="true" />
		
		<cfset var collection = { action="join", name=StructKeyList(arguments.threadIds) } />
		<cfset var thread = "" />
		<cfset var i = "" />
		
		<!--- ColdFusion 8 does not allow a timeout="0" --->
		<cfif arguments.timeout GT 0>
			<cfset collection.timeout = arguments.timeout />
		</cfif>
		
		<!--- ResultArgs are automatically put into the event so we just have to wait for all threads --->
		<cfthread attributeCollection="#collection#" />
		
		<!--- Check for un-handled errors in the threads --->
		<cfloop collection="#arguments.threadIds#" item="i">
			<cfset thread = cfthread[i] />
			
			<cfif StructKeyExists(thread, "caughtException")>
				<cfthrow object="#thread.caughtException#" />
			</cfif>
		</cfloop>
	</cffunction>

	<!---
	PROTECTED FUNCTIONS
	--->
	<cffunction name="convertSecondsToMilliseconds" access="private" returntype="numeric" output="false"
		hint="Convert seconds to milliseconds.">
		<cfargument name="seconds" type="numeric" required="true" />
		<cfreturn arguments.seconds * 1000 />
	</cffunction>

</cfcomponent>