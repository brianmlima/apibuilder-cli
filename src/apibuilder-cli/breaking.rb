require 'ostruct'
require 'json'

module ApibuilderCli


  class SpecHash

    NAME_KEY = "name"

    def SpecHash.name(hash)
      hash[SpecHash::NAME_KEY]
    end

    MODELS_KEY = "models"

    def SpecHash.models(hash)
      hash[SpecHash::MODELS_KEY]
    end

    ENUMS_KEY = "enums"

    def SpecHash.enums(hash)
      hash[SpecHash::ENUMS_KEY]
    end

    RESOURCES_KEY = "resources"

    def SpecHash.resources(hash)
      hash[SpecHash::RESOURCES_KEY]
    end

    PATH_KEY = "path"

    def SpecHash.path(hash)
      hash[SpecHash::PATH_KEY]
    end

    OPERATIONS_KEY = "operations"

    def SpecHash.operations(hash)
      hash[SpecHash::OPERATIONS_KEY]
    end

    FIELDS_KEY = "fields"

    def SpecHash.fields(hash)
      hash[SpecHash::FIELDS_KEY]
    end

    REQUIRED_KEY = "required"

    def SpecHash.required(hash)
      if (hash.has_key?(SpecHash::REQUIRED_KEY)) then
        hash[SpecHash::REQUIRED_KEY]
      else
        true
      end
    end

    def SpecHash.values(hash)
      hash["values"]
    end

    def SpecHash.type(hash)
      hash["type"]
    end
  end

  class SpecTool

    class ModelUtil

      PRIMITIVES = ["boolean", "date-iso8601", "date-time-iso8601", "decimal", "double", "integer", "json", "long", "object", "string", "unit"]

      def ModelUtil.isModel(aType)
        if (ModelUtil::PRIMITIVES.include?("aType"))
          # Is a primitive
          return false
        end
        if (aType[0] == "[")

          return false
        end
        return true
      end
    end


    # finds a field in a model hash by field name
    def SpecTool.findFieldByName(model, fieldName)
      SpecHash.fields(model).each do |field|
        if (fieldName == SpecHash.name(field))
          return field
        end
      end
      return nil
    end


    # finds an enum in a data hash by enum name
    def SpecTool.findEnumByName(data, enumName)
      SpecHash.enums(data).each_pair { |name, enum|
        if (name == enumName)
          return enum
        end
      }
      return nil
    end

    # finds an enum entry in an enum hash by value
    def SpecTool.findEnumEntryByValue(enum, enumValue)
      SpecHash.values(enum).each { |enumEntry|
        if (SpecHash.name(enumEntry) == SpecHash.name(enumValue))
          return enumEntry
        end
      }
      return nil
    end

    def SpecTool.findLocalOperation(remoteOperation, localResource)
      remoteMethod = remoteOperation["method"]
      remotePath = SpecHash.path(remoteOperation)
      SpecHash.operations(localResource).each do |localOperation|
        localMethod = localOperation["method"]
        localPath = SpecHash.path(localOperation)
        if (remoteMethod == localMethod && remotePath == localPath)
          return localOperation
        end
      end
      return nil
    end


    def SpecTool.compare(remoteData, localData)

      breakingChanges = Array.new
      brokenModels = Array.new

      application = SpecHash.name(remoteData)

      breaking = {:isBreaking => true, :isBroken => false}
      broken = {:isBreaking => false, :isBroken => true}

      #############################################
      # BEGIN Check enumerations
      SpecHash.enums(remoteData).each_pair {
          |remoteEnumName, remoteEnum|
        localEnum = findEnumByName(localData, remoteEnumName)
        if (localEnum == nil)
          brokenModels.push(remoteEnumName)
          breakingChanges.push(
              {
                  :type => "ENUM_REMOVED",
                  :location => {:application => application, :enum => remoteEnumName},
                  :severity => breaking,
                  :message => "enums.#{remoteEnumName} does not exist locally"
              })
          next
        end
        SpecHash.values(remoteEnum).each { |remoteEnumValue|
          localEnumValue = findEnumEntryByValue(localEnum, remoteEnumValue)
          if (localEnumValue == nil)
            brokenModels.push(remoteEnumName)
            breakingChanges.push(
                {
                    :type => "ENUM_VALUE_REMOVED",
                    :location => {:application => application, :enum => remoteEnumName, :name => SpecHash.name(remoteEnumValue)},
                    :severity => breaking,
                    :message => "enums.#{remoteEnumName}.values[].name.#{SpecHash.name(remoteEnumValue)} does not exist locally"
                })
            next
          end
        }
      }
      # END Check enumerations
      #############################################

      #############################################
      # BEGIN check models
      ::ApibuilderCli::SpecHash.models(remoteData).each_pair {
          |remoteModelName, remoteModel|
        #puts "#{remoteModleName} #{localData[modelsKey].key?(remoteModleName)}"

        localModel = ::ApibuilderCli::SpecHash.models(localData)[remoteModelName]
        remoteFields = ::ApibuilderCli::SpecHash.fields(remoteModel)
        # localFields = ::ApibuilderCli::SpecHash.fields(localModel)

        #############################################
        # Iterate over the remote model fields
        remoteFields.each {
            |remoteField|
          remoteFieldName = ::ApibuilderCli::SpecHash.name(remoteField)
          localField = ::ApibuilderCli::SpecTool.findFieldByName(localModel, remoteFieldName)
          #Break if remote required field does not exist locally
          if (localField == nil)
            brokenModels.push(remoteModelName)
            breakingChanges.push(
                {
                    :type => "FIELD_REMOVED",
                    :location => {:application => application, :model => remoteModelName, :field => remoteFieldName},
                    :severity => breaking,
                    :message => "models.#{remoteModelName}.fields.#{remoteFieldName} does not exist locally"
                })
            next
          end
          # field exist on both sides, do comparison
          remoteFieldType = ::ApibuilderCli::SpecHash.type(remoteField)
          localFieldType = ::ApibuilderCli::SpecHash.type(localField)
          #  Break if field type has changed
          if (remoteFieldType != localFieldType)
            brokenModels.push(remoteModelName)
            breakingChanges.push(
                {
                    :type => "FIELD_TYPE_CHANGE",
                    :location => {:application => application, :model => remoteModelName, :field => remoteFieldName},
                    :severity => breaking,
                    :message => "field type has changed from #{remoteFieldType} to #{localFieldType}"
                })
          end
          # Break if required has changed
          isRemoteFieldRequired = ::ApibuilderCli::SpecHash.required(remoteField)
          isLocalFieldRequired = ::ApibuilderCli::SpecHash.required(localField)
          if (isRemoteFieldRequired != isLocalFieldRequired)
            brokenModels.push(remoteModelName)
            breakingChanges.push(
                {
                    :type => "FIELD_REQUIRED_CHANGE",
                    :location => {:application => application, :model => remoteModelName, :field => remoteFieldName},
                    :severity => breaking,
                    :message => "#{remoteModelName}.fields.#{remoteFieldName} field required has changed from #{isRemoteFieldRequired} to #{isLocalFieldRequired}"
                })
          end
        }
      }
      # END check models
      #############################################

      remoteResources = SpecHash.resources(remoteData)
      localResources = SpecHash.resources(localData)

      #############################################
      # BEGIN check resources
      remoteResources.each_pair {
          |remoteResourceName, remoteResource|
        if (!localResources.key?(remoteResourceName))
          breakingChanges.push(
              {
                  :type => "RESOURCE_REMOVED",
                  :location => {:application => application, :resource => remoteResourceName},
                  :severity => breaking,
                  :message => "resources.#{remoteResourceName} has been removed"
              })
          next
        end
        localResource = localResources.fetch(remoteResourceName)

        remoteResourcePath = SpecHash.path(remoteResource)
        localResourcePath = SpecHash.path(localResource)

        hasResourcePathChanged = !(remoteResourcePath == localResourcePath)
        if (hasResourcePathChanged)
          remotePath = (remoteResourcePath == nil) ? "Not Defined (defaults to \"#{remoteResourceName}\")" : remoteResourcePath
          localPath = (localResourcePath == nil) ? "Not Defined (defaults to \"#{remoteResourceName}\")" : localResourcePath
          change = {
              :type => "RESOURCE_PATH_CHANGE",
              :location => {:application => application, :resource => remoteResourceName, :path => remotePath},
              :severity => breaking,
              :message => "resources.#{remoteResourceName} path has changed from "\
                               "#{remotePath} to #{localPath}. This will cause any contained operations to break."
          }
          breakingChanges.push(change)
        end

        SpecHash.operations(remoteResource).each {
            |remoteOperation|
          remoteMethod = remoteOperation["method"]
          remotePath = SpecHash.path(remoteOperation)
          localOperation = SpecTool.findLocalOperation(remoteOperation, localResource)
          if (localOperation == nil)
            breakingChanges.push(
                {
                    :type => "OPERATION_REMOVED",
                    :location => {:application => application, :resource => remoteResourceName, :operation => {:metthod => remoteMethod, :path => remotePath}},
                    :severity => breaking,
                    :message => "resources.#{remoteResourceName}.operation{ method: #{remoteMethod} : path: #{remotePath} } has been removed"
                })
            next
          end
          if (hasResourcePathChanged)
            breakingChanges.push(
                {
                    :type => "RESOURCE_PATH_CHANGE_CASCADE",
                    :location => {:application => application, :resource => remoteResourceName, :operation => {:metthod => remoteMethod, :path => remotePath}},
                    :severity => broken,
                    :message => "relative path has changed at the #{remoteResourceName} resource path"
                })
          end
        }
      }
      # END check resources
      #############################################

      return breakingChanges
    end
  end
end
