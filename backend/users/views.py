from django.contrib.auth import authenticate
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from users.models import User
from users.serializers import UserLoginSerializer, UserRegistrationSerializer, UserSerializer


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer

    def get_permissions(self):
        if self.action in ['create', 'register', 'login']:
            return [AllowAny()]
        return [IsAuthenticated()]

    def get_serializer_class(self):
        if self.action in ['create', 'register']:
            return UserRegistrationSerializer
        if self.action == 'login':
            return UserLoginSerializer
        return UserSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        refresh = RefreshToken.for_user(user)
        return Response({
            'user': UserSerializer(user).data,
            'user_url': request.build_absolute_uri(f'/api/auth/users/{user.pk}/'),
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        }, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['post'])
    def register(self, request):
        return self.create(request)

    @action(detail=False, methods=['post'], permission_classes=[AllowAny])
    def login(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = authenticate(
            request,
            email=serializer.validated_data['email'],
            password=serializer.validated_data['password'],
        )
        if not user:
            return Response({'detail': 'Invalid credentials'}, status=status.HTTP_401_UNAUTHORIZED)
        if user.account_status == 'pending':
            return Response(
                {'detail': 'Your account is awaiting administrator approval.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        if user.account_status == 'suspended':
            return Response(
                {'detail': 'Your account has been suspended. Contact support.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        refresh = RefreshToken.for_user(user)
        return Response({
            'user': UserSerializer(user).data,
            'user_url': request.build_absolute_uri(f'/api/auth/users/{user.pk}/'),
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        })

    def retrieve(self, request, *args, **kwargs):
        user = self.get_object()
        if request.user.pk != user.pk and not request.user.is_staff:
            return Response(
                {'detail': 'You may only view your own user record.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response(UserSerializer(user).data)

    @action(detail=False, methods=['get'])
    def me(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

@api_view(['GET'])
@permission_classes([AllowAny])
def auth_root(request):
    return Response({
        'register': request.build_absolute_uri('register/'),
        'login': request.build_absolute_uri('login/'),
        'current_user': request.build_absolute_uri('me/'),
        'current_user_authentication': 'Send Authorization: Bearer <access_token> from the login response.',
    })
