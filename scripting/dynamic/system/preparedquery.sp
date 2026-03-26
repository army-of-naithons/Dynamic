/**
 * =============================================================================
 * Dynamic for SourceMod (C)2016 Matthew J Dunn.   All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

bool _Dynamic_PreparedQuery_Compile(const char[] query, Dynamic obj)
{
	int i=0;
	char byte;

	char[] buffer = new char[strlen(query)+1];
	int bufferpos=0;

	char membername[DYNAMIC_MEMBERNAME_MAXLEN];
	int membernamepos=0;
	bool readingmembername=false;

	bool instring=false;
	char stringbyte;

	while ((byte=query[i++]) != '\0')
	{
		// "   '   ?   `   =   \			" LOL WITHOUT THIS QUOTE THE COMPILER THROWS AN ERROR
		// 034 039 063 096 061 092

		if (byte==96) // `
		{
			buffer[bufferpos++]=byte;
			if (instring)
				continue;

			readingmembername=!readingmembername;

			if (readingmembername)
				membername[membernamepos=0]='\0';
			else
				membername[membernamepos++]='\0';
		}
		else if (byte==34 || byte==39) // " or '
		{
			buffer[bufferpos++]=byte;
			if (instring)
			{
				if (stringbyte==byte) // same string byte
				{
					if (query[i-2] == 92) // \						" LOL WITHOUT THIS QUOTE THE COMPILER THROWS AN ERROR
						continue; // is escaped
				}
				else
					continue; // different string byte

				instring=false;
			}
			else
			{
				instring=true;
				stringbyte=byte;
			}
		}
		else if (byte==63) // ?
		{
			buffer[bufferpos++]='\0';
			obj.PushString(buffer);
			obj.PushString(membername);
			buffer[0]='\0';
			bufferpos=0;
		}
		else // any other char
		{
			if (readingmembername)
				membername[membernamepos++]=byte;

			buffer[bufferpos++]=byte;
		}
	}
	return true;
}

bool _Dynamic_PreparedQuery_Prepare(Dynamic query, Database db, Dynamic parameters, char[] buffer, int buffersize)
{
	int bufferpos = 0;
	int count = query.MemberCount;
	bool issection=true;
	DynamicOffset offset;
	int length;
	char membername[DYNAMIC_MEMBERNAME_MAXLEN];
	char valuebuffer[64];
	for (int i=0; i<count; i++)
	{
		if (issection)
		{
			offset = query.GetMemberOffsetByIndex(i);
			length = query.GetStringLengthByOffset(offset);
			if (length+bufferpos > buffersize)
			{
				LogError("Buffer is to small for Dynamic.PreparedQuery() instance.");
				return false;
			}
			query.GetStringByOffset(offset, buffer[bufferpos], length);
			bufferpos+=length-2;
		}
		else
		{
			query.GetStringByIndex(i, membername, sizeof(membername));
			offset = parameters.GetMemberOffset(membername);

			if (!offset.IsValid)
			{
				LogError("Member `%s` not found in PreparedQuery.SendQuery().", membername);
				return false;
			}

			switch (parameters.GetMemberType(offset))
			{
				case DynamicType_Int, DynamicType_Float, DynamicType_Bool:
				{
					parameters.GetStringByOffset(offset, valuebuffer, sizeof(valuebuffer));
					length = strlen(valuebuffer);
					if (length+bufferpos > buffersize)
					{
						LogError("Buffer is to small for Dynamic.PreparedQuery() instance.");
						return false;
					}
					for (int x=0; x<length; x++)
						buffer[bufferpos++]=valuebuffer[x];
				}
				case DynamicType_String:
				{
					length = parameters.GetStringLengthByOffset(offset)+1;
					char[] strvalue = new char[length];
					parameters.GetStringByOffset(offset, strvalue, length);
					length = (strlen(strvalue)*2)+1;
					char[] strbuffer = new char[length];
					if (!db.Escape(strvalue, strbuffer, length, length))
					{
						LogError("Database.Escape() failed in Dynamic.PreparedQuery().");
						return false;
					}

					if ((length)+bufferpos+2 > buffersize)
					{
						LogError("Buffer is to small for Dynamic.PreparedQuery() instance.");
						return false;
					}
					buffer[bufferpos++] = 39;
					strcopy(buffer[bufferpos], length, strbuffer);
					bufferpos+=length-1;
					buffer[bufferpos++] = 39;
				}
				default:
				{
					LogError("MemberType %d is not supported by PreparedQuery.SendQuery().", parameters.GetMemberType(offset));
					return false;
				}
			}
		}
		issection=!issection;
	}

	return true;
}

bool _Dynamic_PreparedQuery_Execute(Dynamic query, Database db, Dynamic parameters, Function callback, Handle plugin, any data, int buffersize)
{
	char[] buffer = new char[buffersize];
	if (!_Dynamic_PreparedQuery_Prepare(query, db, parameters, buffer, buffersize))
		return false;

	PrivateForward fwd = null;
	if (callback != INVALID_FUNCTION)
	{
		fwd = new PrivateForward( ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell );
		fwd.AddFunction( plugin, callback );
	}

	DataPack pack = new DataPack();
	pack.WriteCell( fwd );
	pack.WriteCell( data );

	db.Query( _Dynamic_PreparedQuery_Callback, buffer, pack );
	return true;
}

static void _Dynamic_PreparedQuery_Callback(Database db, DBResultSet results, const char[] error, any hPack)
{
	if (results == null)
	{
		LogError("Database error: %s", error);
	}

	DataPack pack = view_as<DataPack>( hPack );
	pack.Reset();

	PrivateForward fwd = pack.ReadCell();
	if ( fwd )
	{
		if ( fwd.FunctionCount > 0 )
		{
			Call_StartForward( fwd );
			Call_PushCell( db );
			Call_PushCell( results );
			Call_PushString( error );
			Call_PushCell( pack.ReadCell() );
			Call_Finish();
		}
		fwd.Close();
	}

	pack.Close();
}